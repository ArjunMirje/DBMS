import configparser
import random
import secrets
from datetime import date
from decimal import Decimal
from pathlib import Path
from threading import Event, Lock, Thread
from time import monotonic

import mysql.connector
from flask import Flask, flash, g, jsonify, redirect, render_template, request, url_for

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
SATELLITE_NAME = 'Satellite-01'
SIMULATION_INTERVAL = 10
simulator_stop = Event()
simulator_lock = Lock()
simulator_thread = None


def get_db():
    if 'db' not in g:
        config = configparser.ConfigParser(interpolation=None)
        path = Path(__file__).with_name('config.ini')
        if not config.read(path):
            raise ValueError('Copy config.example.ini to config.ini and enter your MySQL details.')
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


def dashboard_data():
    view = request.args.get('view', 'current')
    if view not in ('current', 'all'):
        raise ValueError('Choose Current 100 readings or All past readings.')
    spacecraft = select('''SELECT c.*, m.name AS mission_name FROM spacecraft c
                          JOIN missions m ON m.mission_id = c.mission_id
                          WHERE c.name = %s''', (SATELLITE_NAME,))
    sensors = select('''SELECT s.*, c.name AS spacecraft_name,
                       CASE s.sensor_type WHEN 'Temperature' THEN 'C' ELSE '%' END AS unit
                       FROM sensors s
                       JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                       WHERE c.name = %s ORDER BY s.sensor_id''', (SATELLITE_NAME,))
    conditions = ['c.name = %s']
    values = [SATELLITE_NAME]
    sensor_id = request.args.get('sensor_id', '')
    if sensor_id:
        conditions.append('s.sensor_id = %s')
        values.append(positive_id(sensor_id))
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
    limit = ' LIMIT 100' if view == 'current' else ''
    readings = select('''SELECT r.*, c.name AS spacecraft_name, s.sensor_type,
                         CASE s.sensor_type WHEN 'Temperature' THEN 'C' ELSE '%' END AS unit,
                         classify_reading(r.measured_value, s.min_value, s.max_value) AS state
                         FROM readings r JOIN sensors s ON s.sensor_id = r.sensor_id
                         JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id'''
                      + where + ' ORDER BY r.recorded_at DESC, r.reading_id DESC' + limit, values)
    alerts = select('''SELECT a.*, r.recorded_at, c.name AS spacecraft_name, s.sensor_type
                      FROM alerts a JOIN readings r ON r.reading_id = a.reading_id
                      JOIN sensors s ON s.sensor_id = r.sensor_id
                      JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                      WHERE c.name = %s
                      ORDER BY a.acknowledged, a.alert_id DESC LIMIT 100''', (SATELLITE_NAME,))
    summary = select('''SELECT c.name AS spacecraft_name, s.sensor_type,
                       CASE s.sensor_type WHEN 'Temperature' THEN 'C' ELSE '%' END AS unit,
                       COUNT(r.reading_id) AS reading_count,
                       MIN(r.measured_value) AS minimum, MAX(r.measured_value) AS maximum,
                       ROUND(AVG(r.measured_value), 2) AS average
                       FROM sensors s JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
                       LEFT JOIN readings r ON r.sensor_id = s.sensor_id
                       WHERE c.name = %s
                       GROUP BY s.sensor_id, c.name, s.sensor_type
                       ORDER BY s.sensor_id''', (SATELLITE_NAME,))
    return dict(spacecraft=spacecraft, sensors=sensors, readings=readings, alerts=alerts,
                summary=summary, view=view, interval=SIMULATION_INTERVAL,
                current_url=url_for('index', **{**request.args.to_dict(), 'view': 'current'}),
                all_url=url_for('index', **{**request.args.to_dict(), 'view': 'all'}))


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
    flash('Status saved.' if changed else 'No status change was needed.')
    return redirect(url_for('index'))


def generate_readings(mode='normal', automatic=False):
    if mode not in ('normal', 'abnormal', 'rollback'):
        raise ValueError('Choose a valid simulation mode.')
    db = get_db()
    db.start_transaction()
    cursor = db.cursor(dictionary=True)
    try:
        cursor.execute('SELECT spacecraft_id, status FROM spacecraft WHERE name = %s FOR UPDATE',
                       (SATELLITE_NAME,))
        craft = cursor.fetchone()
        if craft is None:
            raise ValueError('Satellite-01 is missing. Check the sample data in database/schema.sql.')
        if craft['status'] != 'Active' and mode != 'rollback':
            if automatic:
                db.rollback()
                return 0
            raise ValueError('Set Satellite-01 to Active before generating readings.')
        cursor.execute('SELECT * FROM sensors WHERE spacecraft_id = %s ORDER BY sensor_id',
                       (craft['spacecraft_id'],))
        sensors = cursor.fetchall()
        if not sensors:
            raise ValueError('Satellite-01 needs sensors. Check the sample data in database/schema.sql.')
        for sensor in sensors:
            low = sensor['min_value']
            high = sensor['max_value']
            if mode == 'normal':
                value = round(random.uniform(float(low), float(high)), 2)
            else:
                value = low - Decimal('1.00') if sensor['sensor_type'] == 'Battery' else high + Decimal('1.00')
            cursor.execute('CALL add_reading(%s, %s)', (sensor['sensor_id'], value))
            while cursor.nextset():
                pass
        if mode == 'rollback':
            db.rollback()
        else:
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
            app.logger.warning('Automatic input failed (%s, code %s); retrying in %s seconds.',
                               type(error).__name__, getattr(error, 'errno', None), SIMULATION_INTERVAL)
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
    flash('Rollback complete.' if mode == 'rollback' else f'Saved {count} readings.')
    return redirect(url_for('index'))


@app.post('/alerts/acknowledge')
def acknowledge():
    changed = write('''UPDATE alerts a JOIN readings r ON r.reading_id = a.reading_id
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
    app.logger.error('MySQL error code: %s', error.errno)
    if request.headers.get('Accept') == 'application/json':
        return jsonify(success=False, message='Database unavailable. Try again.'), 503
    return render_template('error.html', message='Cannot complete the database request. '
                           'Check config.ini, start MySQL, and run database/schema.sql once.'), 503


if __name__ == '__main__':
    start_simulator()
    try:
        app.run(host='127.0.0.1', port=5000, debug=False, use_reloader=False)
    finally:
        stop_simulator()
