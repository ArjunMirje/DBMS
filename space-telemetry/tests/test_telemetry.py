"""Integration checks on a separate local MySQL server, never the configured database.

Run with SPACE_TELEMETRY_TEST_PORT set to the isolated server's port.
The test account is root with an empty password on that test server only.
"""
import os
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

import mysql.connector
from flask import g

import app as telemetry


@unittest.skipUnless(os.environ.get('SPACE_TELEMETRY_TEST_PORT'), 'Requires a separate local MySQL test server.')
class TelemetryIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        port = int(os.environ['SPACE_TELEMETRY_TEST_PORT'])
        if port == 3306:
            raise ValueError('Use a separate test server port, not the normal MySQL port.')
        cls.settings = dict(host='127.0.0.1', port=port, user='root', password='',
                            connection_timeout=3)
        cls.database = 'space_telemetry_test_' + uuid.uuid4().hex
        cls.admin = mysql.connector.connect(**cls.settings, autocommit=True)
        cursor = cls.admin.cursor()
        source = Path('database/schema.sql').read_text(encoding='utf-8')
        source = source.replace('space_telemetry', cls.database)
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
                statement = ''
        cursor.execute('SELECT COUNT(*) FROM spacecraft')
        assert cursor.fetchone()[0] == 1, 'Fresh seed must contain only one satellite.'
        # Old databases may contain other satellites: prove they remain untouched.
        cursor.execute("INSERT INTO spacecraft (mission_id, name) VALUES (1, 'Satellite-02')")
        cursor.execute("INSERT INTO sensors (spacecraft_id, sensor_type, min_value, max_value) VALUES (2, 'Temperature', -10, 60)")
        cursor.execute('CALL add_reading(3, 75)')
        while cursor.nextset():
            pass
        cursor.close()

        def isolated_connection():
            if 'db' not in g:
                g.db = mysql.connector.connect(**cls.settings, database=cls.database,
                                              autocommit=False)
            return g.db

        cls.db_patch = patch.object(telemetry, 'get_db', isolated_connection)
        cls.db_patch.start()
        telemetry.app.config['TESTING'] = True

    @classmethod
    def tearDownClass(cls):
        telemetry.stop_simulator()
        cls.db_patch.stop()
        cursor = cls.admin.cursor()
        cursor.execute('DROP DATABASE ' + cls.database)
        cursor.close()
        cls.admin.close()

    def setUp(self):
        telemetry.stop_simulator()
        self.client = telemetry.app.test_client()
        self.sql("UPDATE spacecraft SET status = 'Active' WHERE name = 'Satellite-01'")

    def tearDown(self):
        telemetry.stop_simulator()

    def sql(self, query, values=()):
        cursor = self.admin.cursor()
        try:
            cursor.execute(query, values)
            return cursor.fetchall() if cursor.with_rows else []
        finally:
            cursor.close()

    def counts(self):
        return tuple(self.sql('SELECT (SELECT COUNT(*) FROM readings), (SELECT COUNT(*) FROM alerts)')[0])

    def wait_for(self, condition, timeout=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.025)
        self.fail('Timed out waiting for simulator state.')

    def test_real_ten_second_interval_and_single_worker(self):
        before = self.counts()[0]
        latest_id = self.sql('SELECT MAX(reading_id) FROM readings')[0][0]
        other = self.sql('SELECT COUNT(*) FROM readings WHERE sensor_id = 3')[0][0]
        started = time.monotonic()
        telemetry.start_simulator()
        original_thread = telemetry.simulator_thread
        telemetry.start_simulator()
        self.assertIs(telemetry.simulator_thread, original_thread)
        elapsed = []
        for batch in range(1, 4):
            self.wait_for(lambda: self.counts()[0] >= before + batch * 2, timeout=12)
            elapsed.append(time.monotonic() - started)
            self.assertEqual(self.counts()[0], before + batch * 2)
        telemetry.stop_simulator()
        self.assertLess(elapsed[0], 3)
        self.assertTrue(9 <= elapsed[1] <= 12, elapsed)
        self.assertTrue(19 <= elapsed[2] <= 22, elapsed)
        self.assertEqual(self.sql('SELECT COUNT(*) FROM readings WHERE sensor_id = 3')[0][0], other)
        self.assertEqual(self.sql('SELECT COUNT(*) FROM readings r JOIN sensors s ON s.sensor_id = r.sensor_id WHERE r.reading_id > %s AND s.spacecraft_id = 1 AND (r.measured_value < s.min_value OR r.measured_value > s.max_value)', (latest_id,))[0][0], 0)
        print('Observed automatic batch times (seconds):', [round(value, 2) for value in elapsed])

    def test_browser_reads_never_generate_or_show_other_satellites(self):
        before = self.counts()
        for path in ['/', '/live', '/live?sensor_id=1', '/live?sensor_id=3', '/live?from_date=2026-10-01&to_date=2026-10-31']:
            response = self.client.get(path)
            self.assertEqual(response.status_code, 200)
            self.assertNotIn(b'Satellite-02', response.data)
        self.assertEqual(self.counts(), before)
        self.assertEqual(self.client.get('/live?sensor_id=invalid').status_code, 400)
        self.assertEqual(self.client.get('/live?to_date=9999-12-31').status_code, 400)
        with self.client.get('/static/live.js') as response:
            self.assertEqual(response.status_code, 200)

    def test_manual_alerts_rollback_and_acknowledgement(self):
        before = self.counts()
        response = self.client.post('/simulate', data={'mode': 'abnormal', 'spacecraft_id': 2})
        self.assertEqual(response.status_code, 302)
        self.assertEqual(self.counts(), (before[0] + 2, before[1] + 2))
        self.client.post('/spacecraft/status', data={'status': 'Inactive', 'spacecraft_id': 2})
        self.assertEqual(self.sql('SELECT status FROM spacecraft WHERE spacecraft_id = 2')[0][0], 'Active')
        before = self.counts()
        self.client.post('/simulate', data={'mode': 'rollback'})
        self.assertEqual(self.counts(), before)
        self.client.post('/simulate', data={'mode': 'normal'})
        self.assertEqual(self.counts(), before)
        own_id = self.sql('SELECT MAX(a.alert_id) FROM alerts a JOIN readings r ON r.reading_id = a.reading_id WHERE r.sensor_id = 1')[0][0]
        other_id = self.sql('SELECT a.alert_id FROM alerts a JOIN readings r ON r.reading_id = a.reading_id WHERE r.sensor_id = 3')[0][0]
        self.client.post('/alerts/acknowledge', data={'alert_id': own_id})
        self.client.post('/alerts/acknowledge', data={'alert_id': other_id})
        self.assertEqual(self.sql('SELECT acknowledged FROM alerts WHERE alert_id = %s', (own_id,))[0][0], 1)
        self.assertEqual(self.sql('SELECT acknowledged FROM alerts WHERE alert_id = %s', (other_id,))[0][0], 0)

    def test_failed_second_insert_rolls_back_first_reading_and_alert(self):
        before = self.counts()
        self.sql("""CREATE TRIGGER reject_test_battery BEFORE INSERT ON readings FOR EACH ROW
                    BEGIN IF NEW.sensor_id = 2 THEN
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Integration test failure';
                    END IF; END""")
        try:
            response = self.client.post('/simulate', data={'mode': 'abnormal'})
            self.assertEqual(response.status_code, 503)
            self.assertEqual(self.counts(), before)
        finally:
            self.sql('DROP TRIGGER reject_test_battery')

    def test_pause_resume_and_recovery_after_database_failure(self):
        self.client.post('/spacecraft/status', data={'status': 'Inactive'})
        before = self.counts()
        with patch.object(telemetry, 'SIMULATION_INTERVAL', 0.05), patch.object(telemetry, 'generate_readings', wraps=telemetry.generate_readings) as generate:
            telemetry.start_simulator()
            self.wait_for(lambda: generate.call_count >= 3)
            self.assertEqual(self.counts(), before)
            self.client.post('/spacecraft/status', data={'status': 'Active'})
            self.wait_for(lambda: self.counts()[0] > before[0])
            telemetry.stop_simulator()
        before = self.counts()[0]
        real_generate = telemetry.generate_readings
        calls = []

        def fail_once(*args, **kwargs):
            calls.append(1)
            if len(calls) == 1:
                raise mysql.connector.Error(errno=2003)
            return real_generate(*args, **kwargs)

        with patch.object(telemetry, 'SIMULATION_INTERVAL', 0.05), patch.object(telemetry, 'generate_readings', fail_once):
            telemetry.start_simulator()
            self.wait_for(lambda: self.counts()[0] > before)
            telemetry.stop_simulator()
        self.assertGreaterEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main(verbosity=2)
