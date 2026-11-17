"""One-time migration check against an isolated MySQL test server."""
import os
import unittest
import uuid
from pathlib import Path

import mysql.connector


LEGACY_SCHEMA = r'''
CREATE DATABASE space_telemetry CHARACTER SET utf8mb4;
USE space_telemetry;
CREATE TABLE missions (
 mission_id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80) NOT NULL UNIQUE,
 purpose VARCHAR(200) NOT NULL, start_date DATE NOT NULL
) ENGINE=InnoDB;
CREATE TABLE spacecraft (
 spacecraft_id INT AUTO_INCREMENT PRIMARY KEY, mission_id INT NOT NULL,
 name VARCHAR(80) NOT NULL UNIQUE, status VARCHAR(10) NOT NULL DEFAULT 'Active',
 FOREIGN KEY (mission_id) REFERENCES missions(mission_id), CHECK (status IN ('Active','Inactive'))
) ENGINE=InnoDB;
CREATE TABLE sensors (
 sensor_id INT AUTO_INCREMENT PRIMARY KEY, spacecraft_id INT NOT NULL,
 sensor_type VARCHAR(20) NOT NULL, min_value DECIMAL(10,2) NOT NULL, max_value DECIMAL(10,2) NOT NULL,
 FOREIGN KEY (spacecraft_id) REFERENCES spacecraft(spacecraft_id), UNIQUE (spacecraft_id,sensor_type),
 CHECK (sensor_type IN ('Temperature','Battery')), CHECK (min_value < max_value),
 CHECK (sensor_type <> 'Battery' OR (min_value >= 0 AND max_value <= 100))
) ENGINE=InnoDB;
CREATE TABLE readings (
 reading_id INT AUTO_INCREMENT PRIMARY KEY, sensor_id INT NOT NULL,
 measured_value DECIMAL(10,2) NOT NULL, recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY (sensor_id) REFERENCES sensors(sensor_id), INDEX idx_sensor_time (sensor_id,recorded_at)
) ENGINE=InnoDB;
CREATE TABLE alerts (
 alert_id INT AUTO_INCREMENT PRIMARY KEY, reading_id INT NOT NULL UNIQUE,
 message VARCHAR(200) NOT NULL, acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
 FOREIGN KEY (reading_id) REFERENCES readings(reading_id)
) ENGINE=InnoDB;
DELIMITER $$
CREATE FUNCTION classify_reading(p_value DECIMAL(10,2),p_min DECIMAL(10,2),p_max DECIMAL(10,2))
RETURNS VARCHAR(10) DETERMINISTIC NO SQL
BEGIN IF p_value < p_min THEN RETURN 'LOW'; ELSEIF p_value > p_max THEN RETURN 'HIGH'; ELSE RETURN 'NORMAL'; END IF; END$$
CREATE PROCEDURE add_reading(IN p_sensor_id INT,IN p_value DECIMAL(10,2))
BEGIN INSERT INTO readings(sensor_id,measured_value) VALUES(p_sensor_id,p_value); END$$
CREATE TRIGGER create_reading_alert AFTER INSERT ON readings FOR EACH ROW
BEGIN
 DECLARE v_min DECIMAL(10,2); DECLARE v_max DECIMAL(10,2);
 SELECT min_value,max_value INTO v_min,v_max FROM sensors WHERE sensor_id=NEW.sensor_id;
 IF classify_reading(NEW.measured_value,v_min,v_max) <> 'NORMAL' THEN
  INSERT INTO alerts(reading_id,message) VALUES(NEW.reading_id,'Legacy alert');
 END IF;
END$$
DELIMITER ;
INSERT INTO missions(name,purpose,start_date) VALUES('Earth Observation Demo','Legacy','2026-10-01');
INSERT INTO spacecraft(mission_id,name) VALUES(1,'Satellite-01');
INSERT INTO sensors(spacecraft_id,sensor_type,min_value,max_value)
VALUES(1,'Temperature',-10,60),(1,'Battery',20,100);
CALL add_reading(1,90);
CALL add_reading(2,85);
'''


def run_script(cursor, source):
    delimiter, statement = ';', ''
    for line in source.splitlines():
        if line.startswith('--'):
            continue
        if line.startswith('DELIMITER '):
            delimiter = line.split()[1]
            continue
        statement += line + '\n'
        if statement.rstrip().endswith(delimiter):
            cursor.execute(statement.rstrip()[:-len(delimiter)])
            while cursor.nextset():
                pass
            statement = ''


@unittest.skipUnless(os.environ.get('SPACE_TELEMETRY_TEST_PORT'), 'Requires a separate local MySQL test server.')
class MigrationTests(unittest.TestCase):
    def test_legacy_database_is_upgraded_without_losing_records(self):
        port = int(os.environ['SPACE_TELEMETRY_TEST_PORT'])
        settings = dict(host='127.0.0.1', port=port, user='root', password='', connection_timeout=3)
        database = 'space_telemetry_migration_' + uuid.uuid4().hex
        connection = mysql.connector.connect(**settings, autocommit=True)
        cursor = connection.cursor()
        try:
            run_script(cursor, LEGACY_SCHEMA.replace('space_telemetry', database))
            migration = Path('database/migrate_v2.sql').read_text(encoding='utf-8')
            cursor.execute('SET SQL_SAFE_UPDATES = 1')
            run_script(cursor, migration.replace('space_telemetry', database))
            cursor.execute('SELECT COUNT(*) FROM sensors')
            self.assertEqual(cursor.fetchone()[0], 15)
            cursor.execute('SELECT COUNT(*) FROM readings')
            self.assertEqual(cursor.fetchone()[0], 15)
            cursor.execute('SELECT COUNT(*) FROM alerts WHERE severity IN (\'Warning\',\'Critical\')')
            self.assertEqual(cursor.fetchone()[0], 1)
            cursor.execute("SELECT classify_reading(70,10,60,-10,80,TRUE)")
            self.assertEqual(cursor.fetchone()[0], 'WARNING')
        finally:
            cursor.execute('DROP DATABASE IF EXISTS ' + database)
            cursor.close()
            connection.close()

    def test_previous_diagnostics_are_replaced_by_v3_migration(self):
        port = int(os.environ['SPACE_TELEMETRY_TEST_PORT'])
        settings = dict(host='127.0.0.1', port=port, user='root', password='', connection_timeout=3)
        database = 'space_telemetry_v3_' + uuid.uuid4().hex
        connection = mysql.connector.connect(**settings, autocommit=True)
        cursor = connection.cursor()
        try:
            schema = Path('database/schema.sql').read_text(encoding='utf-8')
            run_script(cursor, schema.replace('space_telemetry', database))
            replacements = [
                ('attitude_error', 'solar_panel_temp', 'Solar-panel temperature', 'Thermal'),
                ('computer_reset_count', 'power_use', 'Total spacecraft power use', 'Power'),
                ('payload_status', 'computer_load', 'Onboard computer load', 'Computing'),
                ('communication_link_health', 'radio_signal', 'Radio signal strength', 'Communication'),
            ]
            for current_code, old_code, old_name, old_category in replacements:
                cursor.execute('''UPDATE telemetry_parameters SET code=%s, name=%s, category=%s
                                  WHERE code=%s''',
                               (old_code, old_name, old_category, current_code))
            cursor.execute('SET SQL_SAFE_UPDATES = 1')
            migration = Path('database/migrate_v3_diagnostics.sql').read_text(encoding='utf-8')
            run_script(cursor, migration.replace('space_telemetry', database))
            cursor.execute('''SELECT COUNT(*) FROM telemetry_parameters
                              WHERE code IN ('attitude_error','computer_reset_count',
                                             'payload_status','communication_link_health')''')
            self.assertEqual(cursor.fetchone()[0], 4)
            cursor.execute('SELECT COUNT(*) FROM readings')
            self.assertEqual(cursor.fetchone()[0], 15)
            cursor.execute('''SELECT s.sensor_id FROM sensors s JOIN telemetry_parameters p
                              ON p.parameter_id=s.parameter_id WHERE p.code='payload_status' ''')
            payload_sensor = cursor.fetchone()[0]
            cursor.execute('CALL add_reading(%s,0,TRUE)', (payload_sensor,))
            while cursor.nextset():
                pass
            cursor.execute("SELECT message FROM alerts ORDER BY alert_id DESC LIMIT 1")
            self.assertEqual(cursor.fetchone()[0], 'Payload operational status reported FAULT')
        finally:
            cursor.execute('DROP DATABASE IF EXISTS ' + database)
            cursor.close()
            connection.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
