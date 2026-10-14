# Line by line code explanation

Updated for the two reading views, reading IDs in alerts, and acknowledgement without page reload. Line numbers match the current application source.

Python generates readings for Satellite-01 immediately at startup and every ten seconds. Each tick gets its own Flask context and MySQL connection. The stored procedure inserts each reading; the trigger inserts any alert. A batch commits together or rolls back together.

The default reading view adds LIMIT 100. The all-history view omits that limit. MySQL retains every committed reading. An alert has its own alert_id and a reading_id foreign key. The page displays reading_id, while its hidden acknowledgement form sends alert_id.

JavaScript fetches saved tables independently of generation and submits acknowledgement in the background. Successful acknowledgement changes only that row. A small revision counter prevents an older table response from restoring the previous button. Error messages are shown only for failed requests.

The Event interrupts the timer at shutdown. The Lock prevents duplicate worker startup. A monotonic clock keeps the interval independent of computer-clock changes. SQL placeholders receive values separately; Jinja prints escaped database values.

## database/schema.sql

**Line 1** - `-- Run once in MySQL Workbench on MySQL 8.0.16 or newer.`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 2** - `-- This creates a NEW database; it never drops an existing database.`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 3** - `CREATE DATABASE space_telemetry CHARACTER SET utf8mb4;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 4** - `USE space_telemetry;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 5** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 6** - `CREATE TABLE missions (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 7** - `mission_id INT AUTO_INCREMENT PRIMARY KEY,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 8** - `name VARCHAR(80) NOT NULL UNIQUE,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 9** - `purpose VARCHAR(200) NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 10** - `start_date DATE NOT NULL`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 11** - `) ENGINE=InnoDB;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 12** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 13** - `CREATE TABLE spacecraft (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 14** - `spacecraft_id INT AUTO_INCREMENT PRIMARY KEY,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 15** - `mission_id INT NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 16** - `name VARCHAR(80) NOT NULL UNIQUE,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 17** - `status VARCHAR(10) NOT NULL DEFAULT 'Active',`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 18** - `FOREIGN KEY (mission_id) REFERENCES missions(mission_id),`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 19** - `CHECK (status IN ('Active', 'Inactive'))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 20** - `) ENGINE=InnoDB;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 21** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 22** - `CREATE TABLE sensors (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 23** - `sensor_id INT AUTO_INCREMENT PRIMARY KEY,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 24** - `spacecraft_id INT NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 25** - `sensor_type VARCHAR(20) NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 26** - `min_value DECIMAL(10,2) NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 27** - `max_value DECIMAL(10,2) NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 28** - `FOREIGN KEY (spacecraft_id) REFERENCES spacecraft(spacecraft_id),`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 29** - `UNIQUE (spacecraft_id, sensor_type),`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 30** - `CHECK (sensor_type IN ('Temperature', 'Battery')),`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 31** - `CHECK (min_value < max_value),`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 32** - `CHECK (sensor_type <> 'Battery' OR (min_value >= 0 AND max_value <= 100))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 33** - `) ENGINE=InnoDB;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 34** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 35** - `CREATE TABLE readings (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 36** - `reading_id INT AUTO_INCREMENT PRIMARY KEY,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 37** - `sensor_id INT NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 38** - `measured_value DECIMAL(10,2) NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 39** - `recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 40** - `FOREIGN KEY (sensor_id) REFERENCES sensors(sensor_id),`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 41** - `INDEX idx_sensor_time (sensor_id, recorded_at)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 42** - `) ENGINE=InnoDB;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 43** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 44** - `CREATE TABLE alerts (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 45** - `alert_id INT AUTO_INCREMENT PRIMARY KEY,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 46** - `reading_id INT NOT NULL UNIQUE,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 47** - `message VARCHAR(200) NOT NULL,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 48** - `acknowledged BOOLEAN NOT NULL DEFAULT FALSE,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 49** - `FOREIGN KEY (reading_id) REFERENCES readings(reading_id)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 50** - `) ENGINE=InnoDB;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 51** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 52** - `DELIMITER $$`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 53** - `CREATE FUNCTION classify_reading (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 54** - `p_value DECIMAL(10,2), p_min DECIMAL(10,2), p_max DECIMAL(10,2)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 55** - `) RETURNS VARCHAR(10)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 56** - `DETERMINISTIC`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 57** - `NO SQL`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 58** - `BEGIN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 59** - `IF p_value < p_min THEN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 60** - `RETURN 'LOW';`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 61** - `ELSEIF p_value > p_max THEN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 62** - `RETURN 'HIGH';`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 63** - `ELSE`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 64** - `RETURN 'NORMAL';`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 65** - `END IF;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 66** - `END$$`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 67** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 68** - `CREATE PROCEDURE add_reading (`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 69** - `IN p_sensor_id INT, IN p_value DECIMAL(10,2)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 70** - `)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 71** - `BEGIN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 72** - `IF p_value IS NULL THEN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 73** - `SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A reading value is required';`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 74** - `END IF;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 75** - `INSERT INTO readings (sensor_id, measured_value)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 76** - `VALUES (p_sensor_id, p_value);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 77** - `END$$`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 78** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 79** - `CREATE TRIGGER create_reading_alert`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 80** - `AFTER INSERT ON readings`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 81** - `FOR EACH ROW`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 82** - `BEGIN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 83** - `DECLARE v_min DECIMAL(10,2);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 84** - `DECLARE v_max DECIMAL(10,2);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 85** - `DECLARE v_state VARCHAR(10);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 86** - `SELECT min_value, max_value INTO v_min, v_max`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 87** - `FROM sensors WHERE sensor_id = NEW.sensor_id;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 88** - `SET v_state = classify_reading(NEW.measured_value, v_min, v_max);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 89** - `IF v_state <> 'NORMAL' THEN`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 90** - `INSERT INTO alerts (reading_id, message)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 91** - `VALUES (NEW.reading_id, CONCAT(v_state, ' reading: ', NEW.measured_value));`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 92** - `END IF;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 93** - `END$$`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 94** - `DELIMITER ;`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 95** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 96** - `INSERT INTO missions (name, purpose, start_date)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 97** - `VALUES ('Earth Observation Demo', 'Simulated spacecraft health monitoring', '2026-10-01');`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 98** - `INSERT INTO spacecraft (mission_id, name)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 99** - `VALUES (1, 'Satellite-01');`

Seeds only one satellite in a new database.

**Line 100** - `-- Limits are chosen for the classroom demo, not real spacecraft specifications.`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 101** - `INSERT INTO sensors (spacecraft_id, sensor_type, min_value, max_value)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 102** - `VALUES (1, 'Temperature', -10, 60), (1, 'Battery', 20, 100);`

Seeds the two sensors for Satellite-01 with classroom example limits.

**Line 103** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 104** - `START TRANSACTION;`

Begins one transaction for the two initial sample readings.

**Line 105** - `CALL add_reading(1, 32);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 106** - `CALL add_reading(2, 85);`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 107** - `COMMIT;`

Commits the two sample readings together; both are normal so no seed alerts are created.

## app.py

**Line 1** - `import configparser`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 2** - `import random`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 3** - `import secrets`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 4** - `from datetime import date`

Imports calendar dates for parsing the reading filters.

**Line 5** - `from decimal import Decimal`

Imports exact decimal values for deliberately abnormal measurements.

**Line 6** - `from pathlib import Path`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 7** - `from threading import Event, Lock, Thread`

Imports the shutdown/timer signal, shared-state lock, and background worker.

**Line 8** - `from time import monotonic`

Imports a timer that is unaffected by changes to the computer clock.

**Line 9** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 10** - `import mysql.connector`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 11** - `from flask import Flask, flash, g, jsonify, redirect, render_template, request, url_for`

Imports Flask, HTML rendering/forms, context data, JSON responses, and URL helpers.

**Line 12** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 13** - `app = Flask(__name__)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 14** - `app.secret_key = secrets.token_hex(32)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 15** - `SATELLITE_NAME = 'Satellite-01'`

Fixes the monitored satellite by its unique database name, including on an existing two-satellite database.

**Line 16** - `SIMULATION_INTERVAL = 10`

Sets the automatic generation and browser-refresh interval to ten seconds.

**Line 17** - `simulator_stop = Event()`

Creates a signal that can interrupt the timer and stop the worker.

**Line 18** - `simulator_lock = Lock()`

Creates a lock for starting the worker and reading/updating shared simulator status.

**Line 19** - `simulator_thread = None`

Stores the worker reference; there is no worker before the application is started.

**Line 20** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 21** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 22** - `def get_db():`

Defines the named Python function; its indented block supplies the behavior.

**Line 23** - `if 'db' not in g:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 24** - `config = configparser.ConfigParser(interpolation=None)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 25** - `path = Path(__file__).with_name('config.ini')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 26** - `if not config.read(path):`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 27** - `raise ValueError('Copy config.example.ini to config.ini and enter your MySQL details.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 28** - `if 'mysql' not in config:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 29** - `raise ValueError('config.ini must contain a [mysql] section.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 30** - `settings = dict(config['mysql'])`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 31** - `settings['port'] = int(settings.get('port', 3306))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 32** - `settings.setdefault('connection_timeout', 3)`

Uses a three-second connection timeout unless the configuration supplies one.

**Line 33** - `g.db = mysql.connector.connect(**settings, autocommit=False)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 34** - `return g.db`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 35** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 36** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 37** - `@app.teardown_appcontext`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 38** - `def close_db(error):`

Defines the named Python function; its indented block supplies the behavior.

**Line 39** - `db = g.pop('db', None)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 40** - `if db is not None:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 41** - `db.close()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 42** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 43** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 44** - `def select(sql, values=()):`

Defines the named Python function; its indented block supplies the behavior.

**Line 45** - `cursor = get_db().cursor(dictionary=True)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 46** - `try:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 47** - `cursor.execute(sql, values)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 48** - `return cursor.fetchall()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 49** - `finally:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 50** - `cursor.close()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 51** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 52** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 53** - `def write(sql, values):`

Defines the named Python function; its indented block supplies the behavior.

**Line 54** - `db = get_db()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 55** - `cursor = db.cursor()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 56** - `try:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 57** - `cursor.execute(sql, values)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 58** - `changed = cursor.rowcount`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 59** - `db.commit()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 60** - `return changed`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 61** - `except Exception:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 62** - `db.rollback()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 63** - `raise`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 64** - `finally:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 65** - `cursor.close()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 66** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 67** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 68** - `def positive_id(value):`

Defines the named Python function; its indented block supplies the behavior.

**Line 69** - `number = int(value)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 70** - `if number < 1:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 71** - `raise ValueError('Select a valid record.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 72** - `return number`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 73** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 74** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 75** - `def dashboard_data():`

Collects the single-satellite data used by both the initial page and live table updates.

**Line 76** - `view = request.args.get('view', 'current')`

Chooses the current-100 view by default, or all history when view=all is in the URL.

**Line 77** - `if view not in ('current', 'all'):`

Accepts only the two supported reading views.

**Line 78** - `raise ValueError('Choose Current 100 readings or All past readings.')`

Rejects an invalid view before querying the database.

**Line 79** - `spacecraft = select('''SELECT c.*, m.name AS mission_name FROM spacecraft c`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 80** - `JOIN missions m ON m.mission_id = c.mission_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 81** - `WHERE c.name = %s''', (SATELLITE_NAME,))`

Restricts this query or update to Satellite-01 using a parameterized name.

**Line 82** - `sensors = select('''SELECT s.*, c.name AS spacecraft_name,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 83** - `CASE s.sensor_type WHEN 'Temperature' THEN 'C' ELSE '%' END AS unit`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 84** - `FROM sensors s`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 85** - `JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 86** - `WHERE c.name = %s ORDER BY s.sensor_id''', (SATELLITE_NAME,))`

Restricts this query or update to Satellite-01 using a parameterized name.

**Line 87** - `conditions = ['c.name = %s']`

Makes the Satellite-01 restriction mandatory for reading queries.

**Line 88** - `values = [SATELLITE_NAME]`

Supplies the satellite name separately from SQL so it remains a parameter.

**Line 89** - `sensor_id = request.args.get('sensor_id', '')`

Reads an optional sensor filter from the URL.

**Line 90** - `if sensor_id:`

Applies the sensor restriction only when a filter was supplied.

**Line 91** - `conditions.append('s.sensor_id = %s')`

Adds a parameterized sensor filter alongside the fixed satellite restriction.

**Line 92** - `values.append(positive_id(sensor_id))`

Validates the sensor ID and adds it to the query parameters.

**Line 93** - `for field, operator in [('from_date', '>='), ('to_date', '<')]:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 94** - `value = request.args.get(field, '')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 95** - `if value:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 96** - `parsed = date.fromisoformat(value)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 97** - `if field == 'to_date':`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 98** - `if parsed == date.max:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 99** - `raise ValueError('End date must be earlier than 9999-12-31.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 100** - `parsed = date.fromordinal(parsed.toordinal() + 1)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 101** - `conditions.append('r.recorded_at ' + operator + ' %s')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 102** - `values.append(parsed)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 103** - `where = ' WHERE ' + ' AND '.join(conditions)`

Combines the mandatory satellite restriction and optional filters with AND.

**Line 104** - `limit = ' LIMIT 100' if view == 'current' else ''`

Limits the current view to 100 matching rows; the all-history view has no row limit.

**Line 105** - `readings = select('''SELECT r.*, c.name AS spacecraft_name, s.sensor_type,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 106** - `CASE s.sensor_type WHEN 'Temperature' THEN 'C' ELSE '%' END AS unit,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 107** - `classify_reading(r.measured_value, s.min_value, s.max_value) AS state`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 108** - `FROM readings r JOIN sensors s ON s.sensor_id = r.sensor_id`

Joins each reading to its sensor to retrieve limits, type, or owning satellite.

**Line 109** - `JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id'''`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 110** - `+ where + ' ORDER BY r.recorded_at DESC, r.reading_id DESC' + limit, values)`

Combines the parameterized filters, newest-first ordering, and selected row limit.

**Line 111** - `alerts = select('''SELECT a.*, r.recorded_at, c.name AS spacecraft_name, s.sensor_type`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 112** - `FROM alerts a JOIN readings r ON r.reading_id = a.reading_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 113** - `JOIN sensors s ON s.sensor_id = r.sensor_id`

Joins each reading to its sensor to retrieve limits, type, or owning satellite.

**Line 114** - `JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 115** - `WHERE c.name = %s`

Restricts this query or update to Satellite-01 using a parameterized name.

**Line 116** - `ORDER BY a.acknowledged, a.alert_id DESC LIMIT 100''', (SATELLITE_NAME,))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 117** - `summary = select('''SELECT c.name AS spacecraft_name, s.sensor_type,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 118** - `CASE s.sensor_type WHEN 'Temperature' THEN 'C' ELSE '%' END AS unit,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 119** - `COUNT(r.reading_id) AS reading_count,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 120** - `MIN(r.measured_value) AS minimum, MAX(r.measured_value) AS maximum,`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 121** - `ROUND(AVG(r.measured_value), 2) AS average`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 122** - `FROM sensors s JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 123** - `LEFT JOIN readings r ON r.sensor_id = s.sensor_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 124** - `WHERE c.name = %s`

Restricts this query or update to Satellite-01 using a parameterized name.

**Line 125** - `GROUP BY s.sensor_id, c.name, s.sensor_type`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 126** - `ORDER BY s.sensor_id''', (SATELLITE_NAME,))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 127** - `return dict(spacecraft=spacecraft, sensors=sensors, readings=readings, alerts=alerts,`

Returns the queried records as the template context.

**Line 128** - `summary=summary, view=view, interval=SIMULATION_INTERVAL,`

Passes statistics, the selected view, and the refresh interval to the page.

**Line 129** - `current_url=url_for('index', **{**request.args.to_dict(), 'view': 'current'}),`

Builds the current-100 link while preserving sensor/date filters and replacing the view parameter.

**Line 130** - `all_url=url_for('index', **{**request.args.to_dict(), 'view': 'all'}))`

Builds the all-history link with the same retained filters.

**Line 131** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 132** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 133** - `@app.get('/')`

Registers a read-only HTTP GET endpoint with Flask.

**Line 134** - `def index():`

Defines the named Python function; its indented block supplies the behavior.

**Line 135** - `return render_template('index.html', **dashboard_data())`

Renders the complete page from the current database data.

**Line 136** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 137** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 138** - `@app.get('/live')`

Registers a read-only HTTP GET endpoint with Flask.

**Line 139** - `def live():`

Returns only the saved telemetry tables; it never generates or inserts readings.

**Line 140** - `return render_template('_telemetry.html', **dashboard_data())`

Renders the shared telemetry fragment used by JavaScript polling.

**Line 141** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 142** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 143** - `@app.post('/spacecraft/status')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 144** - `def change_status():`

Defines the named Python function; its indented block supplies the behavior.

**Line 145** - `status = request.form.get('status')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 146** - `if status not in ('Active', 'Inactive'):`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 147** - `raise ValueError('Choose Active or Inactive.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 148** - `changed = write('UPDATE spacecraft SET status = %s WHERE name = %s',`

Restricts this query or update to Satellite-01 using a parameterized name.

**Line 149** - `(status, SATELLITE_NAME))`

Passes validated values and the fixed satellite name as SQL parameters.

**Line 150** - `flash('Status saved.' if changed else 'No status change was needed.')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 151** - `return redirect(url_for('index'))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 152** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 153** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 154** - `def generate_readings(mode='normal', automatic=False):`

Defines a reusable transaction for both automatic batches and manual demonstrations.

**Line 155** - `if mode not in ('normal', 'abnormal', 'rollback'):`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 156** - `raise ValueError('Choose a valid simulation mode.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 157** - `db = get_db()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 158** - `db.start_transaction()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 159** - `cursor = db.cursor(dictionary=True)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 160** - `try:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 161** - `cursor.execute('SELECT spacecraft_id, status FROM spacecraft WHERE name = %s FOR UPDATE',`

Restricts this query or update to Satellite-01 using a parameterized name.

**Line 162** - `(SATELLITE_NAME,))`

Supplies the fixed satellite name to the preceding parameterized query.

**Line 163** - `craft = cursor.fetchone()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 164** - `if craft is None:`

Rejects an incomplete setup where the fixed satellite does not exist.

**Line 165** - `raise ValueError('Satellite-01 is missing. Check the sample data in database/schema.sql.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 166** - `if craft['status'] != 'Active' and mode != 'rollback':`

Prevents committed input for an Inactive satellite while allowing the discard-only rollback demonstration.

**Line 167** - `if automatic:`

Handles an inactive satellite without failing the automatic worker.

**Line 168** - `db.rollback()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 169** - `return 0`

Reports that the tick skipped input and saved no readings.

**Line 170** - `raise ValueError('Set Satellite-01 to Active before generating readings.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 171** - `cursor.execute('SELECT * FROM sensors WHERE spacecraft_id = %s ORDER BY sensor_id',`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 172** - `(craft['spacecraft_id'],))`

Selects sensors only for the Satellite-01 record already locked in this transaction.

**Line 173** - `sensors = cursor.fetchall()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 174** - `if not sensors:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 175** - `raise ValueError('Satellite-01 needs sensors. Check the sample data in database/schema.sql.')`

Reports a missing or invalid setup record before any batch is committed.

**Line 176** - `for sensor in sensors:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 177** - `low = sensor['min_value']`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 178** - `high = sensor['max_value']`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 179** - `if mode == 'normal':`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 180** - `value = round(random.uniform(float(low), float(high)), 2)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 181** - `else:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 182** - `value = low - Decimal('1.00') if sensor['sensor_type'] == 'Battery' else high + Decimal('1.00')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 183** - `cursor.execute('CALL add_reading(%s, %s)', (sensor['sensor_id'], value))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 184** - `while cursor.nextset():`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 185** - `pass`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 186** - `if mode == 'rollback':`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 187** - `db.rollback()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 188** - `else:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 189** - `db.commit()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 190** - `return len(sensors)`

Reports the number of generated sensor values after commit or deliberate rollback.

**Line 191** - `except Exception:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 192** - `db.rollback()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 193** - `raise`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 194** - `finally:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 195** - `cursor.close()`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 196** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 197** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 198** - `def simulator_loop():`

Defines the background loop that generates one batch every ten seconds.

**Line 199** - `next_run = monotonic()`

Schedules the first batch immediately when the worker starts.

**Line 200** - `while not simulator_stop.is_set():`

Keeps generating until the shutdown signal is set.

**Line 201** - `try:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 202** - `with app.app_context():`

Gives this tick its own Flask context and database connection; teardown closes it at the end.

**Line 203** - `generate_readings(automatic=True)`

Runs one automatic batch in this tick; it skips an Inactive satellite.

**Line 204** - `except (ValueError, mysql.connector.Error) as error:`

Handles setup or database failures without ending the automatic loop.

**Line 205** - `app.logger.warning('Automatic input failed (%s, code %s); retrying in %s seconds.',`

Logs a failed automatic batch and the retry interval.

**Line 206** - `type(error).__name__, getattr(error, 'errno', None), SIMULATION_INTERVAL)`

Logs only the exception category, database code, and retry interval, without database credentials.

**Line 207** - `next_run += SIMULATION_INTERVAL`

Advances the schedule by ten seconds from its previous target time.

**Line 208** - `if next_run <= monotonic():`

Detects a slow batch that missed the next scheduled time.

**Line 209** - `next_run = monotonic() + SIMULATION_INTERVAL`

Skips missed intervals instead of rapidly generating a backlog.

**Line 210** - `simulator_stop.wait(max(0, next_run - monotonic()))`

Waits until the next scheduled tick, waking early when shutdown is requested.

**Line 211** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 212** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 213** - `def start_simulator():`

Starts the worker once in the local application process.

**Line 214** - `global simulator_thread`

Allows this function to replace the module-level worker reference.

**Line 215** - `with simulator_lock:`

Protects worker startup so repeated calls cannot start two background threads in this process.

**Line 216** - `if simulator_thread is not None and simulator_thread.is_alive():`

Checks whether a worker is already running to prevent a second worker in this process.

**Line 217** - `return`

Leaves immediately when no further action is required.

**Line 218** - `simulator_stop.clear()`

Clears the stop signal before starting a worker.

**Line 219** - `simulator_thread = Thread(target=simulator_loop, name='telemetry-simulator', daemon=True)`

Creates a named background thread that will not keep Python alive after the server exits.

**Line 220** - `simulator_thread.start()`

Starts executing the loop in the background.

**Line 221** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 222** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 223** - `def stop_simulator():`

Signals shutdown and briefly waits for an in-progress batch.

**Line 224** - `simulator_stop.set()`

Stops future ticks and interrupts the timer wait.

**Line 225** - `if simulator_thread is not None:`

Waits only if a worker reference exists.

**Line 226** - `simulator_thread.join(timeout=5)`

Allows the worker up to five seconds to finish and close its connection.

**Line 227** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 228** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 229** - `@app.post('/simulate')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 230** - `def simulate():`

Defines the named Python function; its indented block supplies the behavior.

**Line 231** - `mode = request.form.get('mode', 'normal')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 232** - `count = generate_readings(mode)`

Uses the shared transaction helper for the selected manual demonstration.

**Line 233** - `flash('Rollback complete.' if mode == 'rollback' else f'Saved {count} readings.')`

Shows brief manual-action feedback after rollback or commit.

**Line 234** - `return redirect(url_for('index'))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 235** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 236** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 237** - `@app.post('/alerts/acknowledge')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 238** - `def acknowledge():`

Defines the named Python function; its indented block supplies the behavior.

**Line 239** - `changed = write('''UPDATE alerts a JOIN readings r ON r.reading_id = a.reading_id`

Starts a joined alert update so only alerts owned by Satellite-01 can be acknowledged.

**Line 240** - `JOIN sensors s ON s.sensor_id = r.sensor_id`

Joins each reading to its sensor to retrieve limits, type, or owning satellite.

**Line 241** - `JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 242** - `SET a.acknowledged = TRUE`

Marks the matching, satellite-scoped alert as acknowledged.

**Line 243** - `WHERE a.alert_id = %s AND a.acknowledged = FALSE AND c.name = %s''',`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 244** - `(positive_id(request.form.get('alert_id', '')), SATELLITE_NAME))`

Passes validated values and the fixed satellite name as SQL parameters.

**Line 245** - `if request.headers.get('Accept') == 'application/json':`

Detects a background acknowledgement request that expects JSON instead of a redirect.

**Line 246** - `return jsonify(success=bool(changed)), 200 if changed else 404`

Returns success when an open alert was updated, or 404 when none matched; no page navigation occurs.

**Line 247** - `flash('Alert acknowledged.' if changed else 'No open alert matched that ID.')`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 248** - `return redirect(url_for('index'))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 249** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 250** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 251** - `@app.errorhandler(ValueError)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 252** - `def input_error(error):`

Defines the named Python function; its indented block supplies the behavior.

**Line 253** - `if request.headers.get('Accept') == 'application/json':`

Detects a background acknowledgement request that expects JSON instead of a redirect.

**Line 254** - `return jsonify(success=False, message=str(error)), 400`

Returns a JSON validation error so the browser keeps the current page and re-enables the button.

**Line 255** - `if request.path in ('/', '/live'):`

Returns a validation error for both full-page and live-fragment read requests.

**Line 256** - `return render_template('error.html', message=str(error)), 400`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 257** - `flash(str(error))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 258** - `return redirect(url_for('index'))`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 259** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 260** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 261** - `@app.errorhandler(mysql.connector.Error)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 262** - `def database_error(error):`

Defines the named Python function; its indented block supplies the behavior.

**Line 263** - `app.logger.error('MySQL error code: %s', error.errno)`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 264** - `if request.headers.get('Accept') == 'application/json':`

Detects a background acknowledgement request that expects JSON instead of a redirect.

**Line 265** - `return jsonify(success=False, message='Database unavailable. Try again.'), 503`

Returns a safe JSON database error without exposing credentials or internal SQL.

**Line 266** - `return render_template('error.html', message='Cannot complete the database request. '`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 267** - `'Check config.ini, start MySQL, and run database/schema.sql once.'), 503`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 268** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 269** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 270** - `if __name__ == '__main__':`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 271** - `start_simulator()`

Starts automatic input when the documented Python entry point runs.

**Line 272** - `try:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 273** - `app.run(host='127.0.0.1', port=5000, debug=False, use_reloader=False)`

Runs one local Flask server and disables the reloader so it does not start another simulator.

**Line 274** - `finally:`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 275** - `stop_simulator()`

Stops the worker when the web server exits, including Ctrl+C.

## templates/index.html

**Line 1** - `<!doctype html>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 2** - `<html lang="en">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 3** - `<head>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 4** - `<meta charset="utf-8">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 5** - `<meta name="viewport" content="width=device-width, initial-scale=1">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 6** - `<title>Space Telemetry DBMS</title>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 7** - `<link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 8** - `<script src="{{ url_for('static', filename='live.js') }}" defer></script>`

Loads the small refresh script after HTML parsing, so its target elements exist.

**Line 9** - `</head>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 10** - `<body>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 11** - `<main>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 12** - `<h1>Space Telemetry Database Management System</h1>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 13** - `<nav><a href="#setup">Satellite</a> <a href="#simulator">Simulator</a> <a href="#readings">Readings</a> <a href="#alerts">Alerts</a> <a href="#summary">Summary</a></nav>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 14** - `{% for message in get_flashed_messages() %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 15** - `<p class="message" role="status">{{ message }}</p>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 16** - `{% endfor %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 17** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 18** - `<section id="setup">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 19** - `<h2>1. Satellite</h2>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 20** - `<div class="table-wrap"><table><caption>Monitored satellite</caption><thead><tr><th>Name</th><th>Mission</th><th>Status</th><th>Change status</th></tr></thead><tbody>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 21** - `{% for c in spacecraft %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 22** - `<tr><td>{{ c.name }}</td><td>{{ c.mission_name }}</td><td>{{ c.status }}</td><td>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 23** - `<form method="post" action="{{ url_for('change_status') }}">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 24** - `<select name="status" aria-label="Status for {{ c.name }}"><option {% if c.status == 'Active' %}selected{% endif %}>Active</option><option {% if c.status == 'Inactive' %}selected{% endif %}>Inactive</option></select>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 25** - `<button>Save</button>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 26** - `</form>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 27** - `</td></tr>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 28** - `{% else %}<tr><td colspan="4">Satellite-01 is missing. Check the schema sample data.</td></tr>{% endfor %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 29** - `</tbody></table></div>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 30** - `<div class="table-wrap"><table><caption>Satellite sensors</caption><thead><tr><th>ID</th><th>Sensor</th><th>Unit</th><th>Minimum</th><th>Maximum</th></tr></thead><tbody>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 31** - `{% for s in sensors %}<tr><td>{{ s.sensor_id }}</td><td>{{ s.sensor_type }}</td><td>{{ s.unit }}</td><td>{{ s.min_value }}</td><td>{{ s.max_value }}</td></tr>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 32** - `{% else %}<tr><td colspan="5">Satellite-01 has no sensors. Check the schema sample data.</td></tr>{% endfor %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 33** - `</tbody></table></div>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 34** - `</section>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 35** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 36** - `<section id="simulator">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 37** - `<h2>2. Simulator</h2>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 38** - `<form method="post" action="{{ url_for('simulate') }}">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 39** - `<label>Manual demonstration <select name="mode"><option value="normal">Normal readings</option><option value="abnormal">Abnormal readings</option><option value="rollback">Rollback demonstration</option></select></label>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 40** - `<button>Generate once</button>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 41** - `</form>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 42** - `</section>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 43** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 44** - `<section id="readings">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 45** - `<h2>3. Readings</h2>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 46** - `<nav aria-label="Reading views">`

Renders the displayed HTML element or Jinja loop/condition; database values are escaped by Flask.

**Line 47** - `<a href="{{ current_url }}#readings" {% if view == 'current' %}aria-current="page"{% endif %}>Current 100 readings</a>`

Links to the current-100 page with retained filters and marks it selected when active.

**Line 48** - `<a href="{{ all_url }}#readings" {% if view == 'all' %}aria-current="page"{% endif %}>All past readings</a>`

Links to all saved matching readings with retained filters and marks it selected when active.

**Line 49** - `</nav>`

Renders the displayed HTML element or Jinja loop/condition; database values are escaped by Flask.

**Line 50** - `<form method="get" action="{{ url_for('index') }}#readings">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 51** - `<input type="hidden" name="view" value="{{ view }}">`

Keeps the selected reading view when the filter form is submitted.

**Line 52** - `<label>Sensor <select name="sensor_id"><option value="">All</option>{% for s in sensors %}<option value="{{ s.sensor_id }}" {% if request.args.get('sensor_id') == s.sensor_id|string %}selected{% endif %}>{{ s.sensor_type }}</option>{% endfor %}</select></label>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 53** - `<label>From <input type="date" name="from_date" value="{{ request.args.get('from_date', '') }}"></label>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 54** - `<label>To <input type="date" name="to_date" value="{{ request.args.get('to_date', '') }}"></label>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 55** - `<button>Filter</button><a href="{{ url_for('index', view=view) }}#readings">Clear</a>`

Renders the displayed HTML element or Jinja loop/condition; database values are escaped by Flask.

**Line 56** - `</form>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 57** - `</section>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 58** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 59** - `<p id="error-message" class="message" role="alert" hidden></p>`

Creates an initially hidden error region; routine refresh and simulator messages are omitted.

**Line 60** - `<div id="live-data" data-url="{{ url_for('live') }}" data-interval="{{ interval }}">`

Provides the refresh container, endpoint URL, and interval used by JavaScript.

**Line 61** - `{% include '_telemetry.html' %}`

Includes the same telemetry tables returned by the live endpoint.

**Line 62** - `</div>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 63** - `</main>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 64** - `</body>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 65** - `</html>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

## templates/_telemetry.html

**Line 1** - `<div class="table-wrap"><table><caption>{{ 'Current 100 readings' if view == 'current' else 'All past readings' }}</caption><thead><tr><th>ID</th><th>Spacecraft</th><th>Sensor</th><th>Value</th><th>Unit</th><th>Time</th><th>State</th></tr></thead><tbody>`

Names the reading table according to the selected current or all-history view.

**Line 2** - `{% for r in readings %}<tr><td>{{ r.reading_id }}</td><td>{{ r.spacecraft_name }}</td><td>{{ r.sensor_type }}</td><td>{{ r.measured_value }}</td><td>{{ r.unit }}</td><td>{{ r.recorded_at }}</td><td>{{ r.state }}</td></tr>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 3** - `{% else %}<tr><td colspan="7">No readings match these filters.</td></tr>{% endfor %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 4** - `</tbody></table></div>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 5** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 6** - `<section id="alerts">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 7** - `<h2>4. Alerts</h2>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 8** - `<div class="table-wrap"><table><caption>Reading alerts</caption><thead><tr><th>Reading ID</th><th>Spacecraft</th><th>Sensor</th><th>Message</th><th>Time</th><th>Status</th></tr></thead><tbody>`

Labels the first alert column Reading ID to match the identifier shown in the readings table.

**Line 9** - `{% for a in alerts %}<tr><td>{{ a.reading_id }}</td><td>{{ a.spacecraft_name }}</td><td>{{ a.sensor_type }}</td><td>{{ a.message }}</td><td>{{ a.recorded_at }}</td><td>`

Displays the associated reading ID in the alert row, along with that reading's satellite, sensor, message, and time.

**Line 10** - `{% if a.acknowledged %}Acknowledged{% else %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 11** - `<form method="post" action="{{ url_for('acknowledge') }}" data-acknowledge><input type="hidden" name="alert_id" value="{{ a.alert_id }}"><button>Acknowledge</button></form>`

Submits the distinct internal alert ID; JavaScript intercepts this form for acknowledgement without a reload.

**Line 12** - `{% endif %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 13** - `</td></tr>{% else %}<tr><td colspan="6">No alerts yet.</td></tr>{% endfor %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 14** - `</tbody></table></div>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 15** - `</section>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 16** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 17** - `<section id="summary">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 18** - `<h2>5. Summary</h2>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 19** - `<div class="table-wrap"><table><caption>Sensor statistics</caption><thead><tr><th>Spacecraft</th><th>Sensor</th><th>Unit</th><th>Count</th><th>Minimum</th><th>Maximum</th><th>Average</th></tr></thead><tbody>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 20** - `{% for s in summary %}<tr><td>{{ s.spacecraft_name }}</td><td>{{ s.sensor_type }}</td><td>{{ s.unit }}</td><td>{{ s.reading_count }}</td><td>{{ s.minimum if s.minimum is not none else '-' }}</td><td>{{ s.maximum if s.maximum is not none else '-' }}</td><td>{{ s.average if s.average is not none else '-' }}</td></tr>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 21** - `{% else %}<tr><td colspan="7">Satellite-01 has no configured sensors.</td></tr>{% endfor %}`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 22** - `</tbody></table></div>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 23** - `</section>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

## templates/error.html

**Line 1** - `<!doctype html>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 2** - `<html lang="en">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 3** - `<head>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 4** - `<meta charset="utf-8">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 5** - `<meta name="viewport" content="width=device-width, initial-scale=1">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 6** - `<title>Space Telemetry — Request error</title>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 7** - `<link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 8** - `</head>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 9** - `<body>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 10** - `<main>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 11** - `<h1>Request could not be completed</h1>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 12** - `<p role="alert">{{ message }}</p>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 13** - `<p>See README.md for setup and troubleshooting steps.</p>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 14** - `<a href="{{ url_for('index') }}">Return to home</a>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 15** - `</main>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 16** - `</body>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

**Line 17** - `</html>`

Renders the shown HTML element or Jinja loop/condition; displayed database values are escaped by Flask.

## static/style.css

**Line 1** - `* { box-sizing: border-box; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 2** - `body { margin: 0; background: white; color: #222; font: 16px Arial, sans-serif; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 3** - `main { max-width: 1100px; margin: 0 auto; padding: 24px; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 4** - `h1 { font-size: 26px; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 5** - `h2 { font-size: 22px; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 6** - `h3 { font-size: 18px; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 7** - `nav { display: flex; gap: 16px; flex-wrap: wrap; margin: 20px 0; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 8** - `a { color: #174b8b; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 9** - `a[aria-current="page"] { font-weight: bold; }`

Makes the selected reading-view link bold.

**Line 10** - `section { border-top: 1px solid #aaa; padding: 16px 0; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 11** - `form { display: flex; gap: 12px; align-items: end; flex-wrap: wrap; margin: 12px 0; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 12** - `label { display: flex; flex-direction: column; gap: 5px; max-width: 100%; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 13** - `input, select, button { font: inherit; padding: 7px; border: 1px solid #888; border-radius: 2px; max-width: 100%; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 14** - `button { background: #eee; color: #222; cursor: pointer; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 15** - `button:hover { background: #ddd; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 16** - `input:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible { outline: 2px solid #174b8b; outline-offset: 2px; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 17** - `.table-wrap { overflow-x: auto; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 18** - `table { border-collapse: collapse; width: 100%; margin: 12px 0; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 19** - `caption { text-align: left; font-weight: bold; padding: 8px 0; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 20** - `th, td { border: 1px solid #bbb; padding: 8px; text-align: left; vertical-align: top; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 21** - `th { background: #f2f2f2; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 22** - `td form { margin: 0; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 23** - `.message { padding: 12px; border: 1px solid #888; background: #f4f4f4; overflow-wrap: anywhere; }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 24** - `@media (max-width: 600px) { main { padding: 12px; } h1 { font-size: 22px; } }`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

## static/live.js

**Line 1** - `const liveData = document.getElementById('live-data');`

Finds the container holding saved reading, alert, and summary tables.

**Line 2** - `const errorMessage = document.getElementById('error-message');`

Finds the initially hidden message used only when a request fails.

**Line 3** - `const interval = Number(liveData.dataset.interval) * 1000;`

Converts the ten-second interval to milliseconds.

**Line 4** - `let pending = 0, revision = 0;`

Tracks in-progress acknowledgements and completed changes to avoid replacing their rows with stale fetched HTML.

**Line 5** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 6** - `function showError(message = '') {`

Defines a shared helper to show an error or clear it with an empty message.

**Line 7** - `errorMessage.textContent = message;`

Writes the error as plain text.

**Line 8** - `errorMessage.hidden = !message;`

Shows the message only when there is an actual error.

**Line 9** - `}`

Closes the current JavaScript function or block.

**Line 10** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 11** - `async function refreshTables() {`

Defines the read-only background refresh operation.

**Line 12** - `const version = revision;`

Remembers the acknowledgement state when the table request begins.

**Line 13** - `try {`

Begins the successful-fetch path; errors are handled below.

**Line 14** - `const response = await fetch(liveData.dataset.url + window.location.search, { cache: 'no-store' });`

Fetches /live with the selected reading view and sensor/date filters, bypassing cached data.

**Line 15** - `if (!response.ok) throw new Error('Unable to refresh readings.');`

Handles an unsuccessful response without replacing the tables with an error page.

**Line 16** - `const html = await response.text();`

Reads the server-rendered HTML fragment.

**Line 17** - `if (!pending && version === revision && !liveData.contains(document.activeElement)) liveData.innerHTML = html;`

Updates tables only when no acknowledgement is pending, no newer acknowledgement completed, and no table control has focus.

**Line 18** - `showError();`

Clears an old error after a successful request without showing routine timestamp/status text.

**Line 19** - `} catch (error) {`

Handles a failed fetch or an error response.

**Line 20** - `showError(error.message);`

Shows a concise error while keeping the current page and tables.

**Line 21** - `} finally {`

Runs cleanup or schedules the next refresh after either success or failure.

**Line 22** - `window.setTimeout(refreshTables, interval);`

Schedules the next refresh after ten seconds.

**Line 23** - `}`

Closes the current JavaScript function or block.

**Line 24** - `}`

Closes the current JavaScript function or block.

**Line 25** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 26** - `liveData.addEventListener('submit', async event => {`

Delegates acknowledgement handling to the table container, so it also works after table refreshes.

**Line 27** - `const form = event.target;`

Gets the form being submitted.

**Line 28** - `if (!form.matches('[data-acknowledge]')) return;`

Intercepts only alert acknowledgement forms.

**Line 29** - `event.preventDefault();`

Stops the normal browser form submission and page reload.

**Line 30** - `const button = form.querySelector('button');`

Finds this row's acknowledgement button.

**Line 31** - `if (button.disabled) return;`

Avoids sending a duplicate submission while this button is busy.

**Line 32** - `button.disabled = true;`

Disables the button while its database update is pending.

**Line 33** - `pending++;`

Records one in-progress acknowledgement.

**Line 34** - `try {`

Begins the successful-fetch path; errors are handled below.

**Line 35** - `const response = await fetch(form.action, { method: 'POST', body: new FormData(form), headers: { Accept: 'application/json' } });`

Posts the existing hidden internal alert ID and requests a JSON result, without changing the page URL.

**Line 36** - `const result = await response.json();`

Reads the backend acknowledgement result.

**Line 37** - `if (!response.ok || !result.success) throw new Error(result.message || 'Unable to acknowledge alert.');`

Treats HTTP/database/validation failures as an error instead of falsely displaying Acknowledged.

**Line 38** - `form.replaceWith('Acknowledged');`

Updates only the affected alert cell after the database confirms success.

**Line 39** - `showError();`

Clears an old error after a successful request without showing routine timestamp/status text.

**Line 40** - `} catch (error) {`

Handles a failed fetch or an error response.

**Line 41** - `showError(error.message);`

Shows a concise error while keeping the current page and tables.

**Line 42** - `} finally {`

Runs cleanup or schedules the next refresh after either success or failure.

**Line 43** - `button.disabled = false;`

Makes the button usable again if the request failed.

**Line 44** - `pending--;`

Marks this acknowledgement request as finished.

**Line 45** - `revision++;`

Invalidates any older refresh response that could recreate the previous acknowledgement button.

**Line 46** - `}`

Closes the current JavaScript function or block.

**Line 47** - `});`

Closes the delegated form-submission handler.

**Line 48** - `(blank)`

Blank line separating logical blocks; it has no executable effect.

**Line 49** - `window.setTimeout(refreshTables, interval);`

Schedules the next refresh after ten seconds.

## config.example.ini

**Line 1** - `[mysql]`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 2** - `host = 127.0.0.1`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 3** - `port = 3306`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 4** - `user = root`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 5** - `password = YOUR_MYSQL_PASSWORD`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 6** - `database = space_telemetry`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

## requirements.txt

**Line 1** - `Flask>=3.1,<4`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.

**Line 2** - `mysql-connector-python>=9.5,<10`

Continues the preceding Python expression, SQL statement, or block; indentation and parentheses connect it to that statement.
