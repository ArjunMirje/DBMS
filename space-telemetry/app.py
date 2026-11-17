import configparser
import random
import secrets
from datetime import date
from pathlib import Path
from threading import Event, Lock, Thread
from time import monotonic

import mysql.connector
from flask import Flask, flash, g, jsonify, redirect, render_template, request, url_for


app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
SATELLITE_NAME = 'Satellite-01'
SIMULATION_INTERVAL = 10
VALID_CATEGORIES = ('Thermal', 'Power', 'Attitude', 'Computing', 'Communication', 'Payload')
VALID_STATES = ('NORMAL', 'WARNING', 'CRITICAL', 'STANDBY')
simulator_stop = Event()
simulator_lock = Lock()
simulator_thread = None


def get_db():
    if 'db' not in g:
        config = configparser.ConfigParser(interpolation=None)
        path = Path(__file__).with_name('config.ini')
        if not config.read(path):
            raise ValueError('Create config.ini and enter your local MySQL details.')
        if 'mysql' not in config:
            raise ValueError('config.ini must contain a [mysql] section.')
        settings = dict(config['mysql'])
        settings['port'] = int(settings.get('port', 3306))
        settings.setdefault('connection_timeout', 3)
        g.db = mysql.connector.connect(**settings, autocommit=False)
    return g.db


@app.teardown_appcontext
def close_db(error):
    db = g.pop('db', None)
    if db is not None:
        db.close()


def select(sql, values=()):
    cursor = get_db().cursor(dictionary=True)
    try:
        cursor.execute(sql, values)
        return cursor.fetchall()
    finally:
        cursor.close()


def write(sql, values):
    db = get_db()
    cursor = db.cursor()
    try:
        cursor.execute(sql, values)
        changed = cursor.rowcount
        db.commit()
        return changed
    except Exception:
        db.rollback()
        raise
    finally:
        cursor.close()


def positive_id(value):
    number = int(value)
    if number < 1:
        raise ValueError('Select a valid record.')
    return number


CLASSIFY_SQL = '''classify_reading(
    r.measured_value, p.normal_min, p.normal_max,
    p.critical_min, p.critical_max, r.expected_active
)'''


def trend_points(rows):
    if not rows:
        return ''
    values = [float(row['measured_value']) for row in rows]
    low, high = min(values), max(values)
    if low == high:
        low -= 1
        high += 1
    width, height, padding = 600, 150, 8
    last = max(len(values) - 1, 1)
    return ' '.join(
        f'{padding + index * (width - 2 * padding) / last:.1f},'
        f'{height - padding - (value - low) * (height - 2 * padding) / (high - low):.1f}'
        for index, value in enumerate(values)
    )


PAYLOAD_STATES = {0: 'FAULT', 1: 'IDLE', 2: 'READY', 3: 'IMAGING'}


def add_display_values(rows):
    for row in rows:
        value = row.get('measured_value')
        if row.get('code') == 'payload_status' and value is not None:
            row['display_value'] = PAYLOAD_STATES.get(int(value), 'UNKNOWN')
        else:
            row['display_value'] = value


def dashboard_data():
    view = request.args.get('view', 'current')
    category = request.args.get('category', '')
    state = request.args.get('state', '')
    if view not in ('current', 'all'):
        raise ValueError('Choose Current 100 readings or All past readings.')
    if category and category not in VALID_CATEGORIES:
        raise ValueError('Choose a valid telemetry category.')
    if state and state not in VALID_STATES:
        raise ValueError('Choose a valid telemetry state.')

    spacecraft = select('''SELECT c.*, m.name AS mission_name, m.purpose
                           FROM spacecraft c
                           JOIN missions m ON m.mission_id = c.mission_id
                           WHERE c.name = %s''', (SATELLITE_NAME,))
    sensors = select('''SELECT s.sensor_id, c.name AS spacecraft_name, p.*
                        FROM sensors s
                        JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                        JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
                        WHERE c.name = %s
                        ORDER BY p.category, p.parameter_id''', (SATELLITE_NAME,))
    latest = select(f'''SELECT s.sensor_id, p.code, p.name AS sensor_name, p.category, p.unit,
                        p.normal_min, p.normal_max, p.critical_min, p.critical_max,
                        r.reading_id, r.measured_value, r.recorded_at,
                        CASE WHEN r.reading_id IS NULL THEN 'NO DATA' ELSE {CLASSIFY_SQL} END AS state
                        FROM sensors s
                        JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                        JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
                        LEFT JOIN readings r ON r.reading_id = (
                            SELECT r2.reading_id FROM readings r2
                            WHERE r2.sensor_id = s.sensor_id
                            ORDER BY r2.recorded_at DESC, r2.reading_id DESC LIMIT 1
                        )
                        WHERE c.name = %s
                        ORDER BY p.category, p.parameter_id''', (SATELLITE_NAME,))

    conditions = ['c.name = %s']
    values = [SATELLITE_NAME]
    sensor_id = request.args.get('sensor_id', '')
    selected_sensor_id = positive_id(sensor_id) if sensor_id else None
    if selected_sensor_id:
        conditions.append('s.sensor_id = %s')
        values.append(selected_sensor_id)
    if category:
        conditions.append('p.category = %s')
        values.append(category)
    for field, operator in [('from_date', '>='), ('to_date', '<')]:
        value = request.args.get(field, '')
        if value:
            parsed = date.fromisoformat(value)
            if field == 'to_date':
                if parsed == date.max:
                    raise ValueError('End date must be earlier than 9999-12-31.')
                parsed = date.fromordinal(parsed.toordinal() + 1)
            conditions.append('r.recorded_at ' + operator + ' %s')
            values.append(parsed)
    where = ' WHERE ' + ' AND '.join(conditions)
    reading_sql = f'''SELECT r.reading_id, r.measured_value, r.recorded_at,
                       c.name AS spacecraft_name, s.sensor_id, p.code, p.name AS sensor_name,
                       p.category, p.unit, {CLASSIFY_SQL} AS state
                       FROM readings r
                       JOIN sensors s ON s.sensor_id = r.sensor_id
                       JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                       JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id''' + where
    if state:
        reading_sql = 'SELECT * FROM (' + reading_sql + ') filtered_readings WHERE state = %s'
        values.append(state)
    limit = ' LIMIT 100' if view == 'current' else ''
    readings = select(reading_sql + ' ORDER BY recorded_at DESC, reading_id DESC' + limit, values)
    add_display_values(latest)
    add_display_values(readings)

    alerts = select('''SELECT a.*, r.recorded_at, r.measured_value,
                       c.name AS spacecraft_name, p.name AS sensor_name, p.unit
                       FROM alerts a
                       JOIN readings r ON r.reading_id = a.reading_id
                       JOIN sensors s ON s.sensor_id = r.sensor_id
                       JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                       JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
                       WHERE c.name = %s
                       ORDER BY a.acknowledged, FIELD(a.severity, 'Critical', 'Warning'),
                                a.alert_id DESC LIMIT 100''', (SATELLITE_NAME,))
    summary = select('''SELECT c.name AS spacecraft_name, p.code, p.name AS sensor_name,
                        p.category, p.unit, COUNT(r.reading_id) AS reading_count,
                        MIN(r.measured_value) AS minimum, MAX(r.measured_value) AS maximum,
                        ROUND(AVG(r.measured_value), 2) AS average
                        FROM sensors s
                        JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                        JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
                        LEFT JOIN readings r ON r.sensor_id = s.sensor_id
                        WHERE c.name = %s AND p.code <> 'payload_status'
                        GROUP BY s.sensor_id, c.name, p.code, p.name, p.category, p.unit, p.parameter_id
                        ORDER BY p.category, p.parameter_id''', (SATELLITE_NAME,))

    trend_sensor_id = selected_sensor_id or (sensors[0]['sensor_id'] if sensors else None)
    trend = []
    if trend_sensor_id:
        trend = select(f'''SELECT * FROM (
                           SELECT r.measured_value, r.recorded_at, p.name AS sensor_name, p.unit,
                                  {CLASSIFY_SQL} AS state
                           FROM readings r
                           JOIN sensors s ON s.sensor_id = r.sensor_id
                           JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                           JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
                           WHERE c.name = %s AND s.sensor_id = %s
                           ORDER BY r.recorded_at DESC, r.reading_id DESC LIMIT 30
                           ) recent ORDER BY recorded_at''', (SATELLITE_NAME, trend_sensor_id))

    states = [item['state'] for item in latest if item['state'] != 'NO DATA']
    if 'CRITICAL' in states:
        health = 'CRITICAL'
    elif 'WARNING' in states:
        health = 'WARNING'
    elif states:
        health = 'NORMAL'
    else:
        health = 'NO DATA'
    state_counts = {name: states.count(name) for name in VALID_STATES}
    open_alert_count = sum(not alert['acknowledged'] for alert in alerts)
    query_args = request.args.to_dict()
    return dict(
        spacecraft=spacecraft, sensors=sensors, latest=latest, readings=readings,
        alerts=alerts, summary=summary, trend=trend, trend_points=trend_points(trend),
        trend_sensor_id=trend_sensor_id, health=health, state_counts=state_counts,
        open_alert_count=open_alert_count, categories=VALID_CATEGORIES, states=VALID_STATES,
        view=view, interval=SIMULATION_INTERVAL,
        current_url=url_for('index', **{**query_args, 'view': 'current'}),
        all_url=url_for('index', **{**query_args, 'view': 'all'}),
    )


@app.get('/')
def index():
    return render_template('index.html', **dashboard_data())


@app.get('/live')
def live():
    return render_template('_telemetry.html', **dashboard_data())


@app.post('/spacecraft/status')
def change_status():
    status = request.form.get('status')
    if status not in ('Active', 'Inactive'):
        raise ValueError('Choose Active or Inactive.')
    changed = write('UPDATE spacecraft SET status = %s WHERE name = %s',
                    (status, SATELLITE_NAME))
    flash('Satellite status saved.' if changed else 'No status change was needed.')
    return redirect(url_for('index'))


def expected_active(sensor, craft):
    rule = sensor['activity_rule']
    return (rule == 'Always'
            or rule == craft.get('orbit_state')
            or rule == craft.get('contact_state'))


def rounded(value, places):
    return round(value, int(places))


def clamp(value, lower, upper):
    if lower is not None:
        value = max(value, float(lower))
    if upper is not None:
        value = min(value, float(upper))
    return value


def normal_value(sensor, craft):
    code = sensor['code']
    if not expected_active(sensor, craft):
        return 0

    nominal = float(sensor['nominal_value'])
    step = float(sensor['max_step'])
    previous = float(sensor['previous_value']) if sensor.get('previous_value') is not None else nominal
    lower, upper = sensor.get('normal_min'), sensor.get('normal_max')
    if lower is not None and previous < float(lower):
        previous = nominal
    if upper is not None and previous > float(upper):
        previous = nominal

    if code == 'battery_charge':
        direction = 0.18 if craft.get('orbit_state') == 'Sunlight' else -0.28
        value = previous + direction + random.uniform(-0.08, 0.08)
    elif code == 'battery_current':
        target = 0.30 if craft.get('orbit_state') == 'Sunlight' else -1.20
        value = target + random.uniform(-step, step)
    elif code == 'storage_used':
        direction = -0.50 if craft.get('contact_state') == 'Ground contact' else 0.20
        value = previous + direction + random.uniform(-0.10, 0.10)
    elif code == 'computer_reset_count':
        value = 0
    elif code == 'payload_status':
        value = random.choice((1, 2, 2, 2, 3))
    else:
        value = previous + random.uniform(-step, step)
    return rounded(clamp(value, lower, upper), sensor['decimal_places'])


def fault_value(sensor, severity):
    normal_min = sensor.get('normal_min')
    normal_max = sensor.get('normal_max')
    critical_min = sensor.get('critical_min')
    critical_max = sensor.get('critical_max')
    code = sensor['code']
    prefer_high = code in {'storage_used', 'computer_reset_count', 'attitude_error'}

    if severity == 'warning':
        lower = ((float(critical_min) + float(normal_min)) / 2
                 if critical_min is not None and normal_min is not None
                 and critical_min < normal_min else None)
        upper = ((float(normal_max) + float(critical_max)) / 2
                 if normal_max is not None and critical_max is not None
                 and normal_max < critical_max else None)
        choices = [value for value in ([upper, lower] if prefer_high else [lower, upper])
                   if value is not None]
    else:
        step = max(float(sensor['max_step']), 0.1)
        lower = float(critical_min) - step if critical_min is not None else None
        upper = float(critical_max) + step if critical_max is not None else None
        choices = [value for value in ([upper, lower] if prefer_high else [lower, upper])
                   if value is not None]
    if not choices:
        raise ValueError(f"{sensor['name']} does not have a {severity} range.")
    return rounded(choices[0], sensor['decimal_places'])


def supports_fault(sensor, severity):
    if severity == 'warning':
        return ((sensor.get('critical_min') is not None and sensor.get('normal_min') is not None
                 and sensor['critical_min'] < sensor['normal_min'])
                or (sensor.get('normal_max') is not None and sensor.get('critical_max') is not None
                    and sensor['normal_max'] < sensor['critical_max']))
    return sensor.get('critical_min') is not None or sensor.get('critical_max') is not None


def advance_context(craft):
    step = int(craft.get('simulation_step') or 0) + 1
    return {
        'simulation_step': step,
        'orbit_state': 'Sunlight' if step % 18 < 12 else 'Eclipse',
        'contact_state': 'Ground contact' if step % 30 < 6 else 'No contact',
    }


def generate_readings(mode='normal', automatic=False):
    if mode == 'abnormal':
        mode = 'critical'
    if mode not in ('normal', 'warning', 'critical'):
        raise ValueError('Choose a valid simulation mode.')
    db = get_db()
    db.start_transaction()
    cursor = db.cursor(dictionary=True)
    try:
        cursor.execute('''SELECT spacecraft_id, status, orbit_state, contact_state, simulation_step
                          FROM spacecraft WHERE name = %s FOR UPDATE''', (SATELLITE_NAME,))
        craft = cursor.fetchone()
        if craft is None:
            raise ValueError('Satellite-01 is missing. Run database/schema.sql.')
        if craft['status'] != 'Active':
            if automatic:
                db.rollback()
                return 0
            raise ValueError('Set Satellite-01 to Active before generating readings.')
        if automatic:
            craft.update(advance_context(craft))
            cursor.execute('''UPDATE spacecraft
                              SET orbit_state = %s, contact_state = %s, simulation_step = %s
                              WHERE spacecraft_id = %s''',
                           (craft['orbit_state'], craft['contact_state'],
                            craft['simulation_step'], craft['spacecraft_id']))
        cursor.execute('''SELECT s.sensor_id, p.*,
                          (SELECT r.measured_value FROM readings r
                           WHERE r.sensor_id = s.sensor_id
                           ORDER BY r.recorded_at DESC, r.reading_id DESC LIMIT 1) AS previous_value
                          FROM sensors s
                          JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
                          WHERE s.spacecraft_id = %s ORDER BY p.parameter_id''',
                       (craft['spacecraft_id'],))
        sensors = cursor.fetchall()
        if not sensors:
            raise ValueError('Satellite-01 needs telemetry sensors. Run database/schema.sql.')

        batch_mode = mode
        if automatic:
            event_roll = random.random()
            batch_mode = 'critical' if event_roll < 0.01 else 'warning' if event_roll < 0.05 else 'normal'
        severity = batch_mode
        eligible_sensors = [sensor for sensor in sensors
                            if expected_active(sensor, craft) and supports_fault(sensor, severity)]
        fault_sensor = random.choice(eligible_sensors) if batch_mode in ('warning', 'critical') else None

        for sensor in sensors:
            active = expected_active(sensor, craft)
            value = (fault_value(sensor, severity)
                     if sensor is fault_sensor else normal_value(sensor, craft))
            cursor.execute('CALL add_reading(%s, %s, %s)',
                           (sensor['sensor_id'], value, active))
            while cursor.nextset():
                pass
        db.commit()
        return len(sensors)
    except Exception:
        db.rollback()
        raise
    finally:
        cursor.close()


def simulator_loop():
    next_run = monotonic()
    while not simulator_stop.is_set():
        try:
            with app.app_context():
                generate_readings(automatic=True)
        except (ValueError, mysql.connector.Error) as error:
            app.logger.warning('Automatic input failed (%s, code %s): %s; retrying in %s seconds.',
                               type(error).__name__, getattr(error, 'errno', None), error,
                               SIMULATION_INTERVAL)
        next_run += SIMULATION_INTERVAL
        if next_run <= monotonic():
            next_run = monotonic() + SIMULATION_INTERVAL
        simulator_stop.wait(max(0, next_run - monotonic()))


def start_simulator():
    global simulator_thread
    with simulator_lock:
        if simulator_thread is not None and simulator_thread.is_alive():
            return
        simulator_stop.clear()
        simulator_thread = Thread(target=simulator_loop, name='telemetry-simulator', daemon=True)
        simulator_thread.start()


def stop_simulator():
    simulator_stop.set()
    if simulator_thread is not None:
        simulator_thread.join(timeout=5)


@app.post('/simulate')
def simulate():
    mode = request.form.get('mode', 'normal')
    count = generate_readings(mode)
    messages = {
        'normal': f'Saved {count} normal telemetry readings.',
        'warning': f'Saved {count} readings with one warning.',
        'critical': f'Saved {count} readings with one critical emergency.',
        'abnormal': f'Saved {count} readings with one critical emergency.',
    }
    flash(messages.get(mode, f'Saved {count} readings.'))
    return redirect(url_for('index'))


@app.post('/alerts/acknowledge')
def acknowledge():
    changed = write('''UPDATE alerts a
                       JOIN readings r ON r.reading_id = a.reading_id
                       JOIN sensors s ON s.sensor_id = r.sensor_id
                       JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                       SET a.acknowledged = TRUE
                       WHERE a.alert_id = %s AND a.acknowledged = FALSE AND c.name = %s''',
                    (positive_id(request.form.get('alert_id', '')), SATELLITE_NAME))
    if request.headers.get('Accept') == 'application/json':
        return jsonify(success=bool(changed)), 200 if changed else 404
    flash('Alert acknowledged.' if changed else 'No open alert matched that ID.')
    return redirect(url_for('index'))


@app.errorhandler(ValueError)
def input_error(error):
    if request.headers.get('Accept') == 'application/json':
        return jsonify(success=False, message=str(error)), 400
    if request.path in ('/', '/live'):
        return render_template('error.html', message=str(error)), 400
    flash(str(error))
    return redirect(url_for('index'))


@app.errorhandler(mysql.connector.Error)
def database_error(error):
    app.logger.error('MySQL error code %s: %s', error.errno, error)
    if request.headers.get('Accept') == 'application/json':
        return jsonify(success=False, message='Database unavailable. Try again.'), 503
    return render_template('error.html', message='Cannot complete the database request. '
                           'Start MySQL and install the current database schema or migration.'), 503


if __name__ == '__main__':
    start_simulator()
    try:
        app.run(host='127.0.0.1', port=5000, debug=False, use_reloader=False)
    finally:
        stop_simulator()
