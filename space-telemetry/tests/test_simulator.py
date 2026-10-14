"""Timer, connection lifecycle, transaction, and page checks without live MySQL."""
import configparser
import threading
import time
import unittest
from decimal import Decimal
from unittest.mock import MagicMock, patch

import mysql.connector

import app as telemetry


def batch_connection(status='Active'):
    db = MagicMock()
    cursor = db.cursor.return_value
    cursor.fetchone.return_value = {'spacecraft_id': 7, 'status': status}
    cursor.fetchall.return_value = [
        {'sensor_id': 10, 'sensor_type': 'Temperature', 'min_value': Decimal('-10'), 'max_value': Decimal('60')},
        {'sensor_id': 11, 'sensor_type': 'Battery', 'min_value': Decimal('20'), 'max_value': Decimal('100')},
    ]
    cursor.nextset.return_value = None
    return db


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        telemetry.stop_simulator()
        telemetry.app.config['TESTING'] = True
        self.client = telemetry.app.test_client()

    def tearDown(self):
        telemetry.stop_simulator()

    def test_real_timer_and_one_connection_per_batch(self):
        config = configparser.ConfigParser()
        config.read_dict({'mysql': {'host': '127.0.0.1', 'port': '3306', 'user': 'test', 'password': '', 'database': 'test'}})
        config.read = MagicMock(return_value=['test-config.ini'])
        connections, times = [], []
        third_batch = threading.Event()

        def connect(**settings):
            db = batch_connection()
            connections.append(db)
            times.append(time.monotonic())
            if len(connections) == 3:
                third_batch.set()
            return db

        with patch.object(telemetry.configparser, 'ConfigParser', return_value=config), patch.object(telemetry.mysql.connector, 'connect', connect):
            telemetry.start_simulator()
            worker = telemetry.simulator_thread
            telemetry.start_simulator()
            self.assertIs(telemetry.simulator_thread, worker)
            self.assertTrue(third_batch.wait(timeout=24))
            telemetry.stop_simulator()
        self.assertEqual(len(connections), 3)
        intervals = [times[i] - times[i - 1] for i in (1, 2)]
        for interval in intervals:
            self.assertTrue(9.5 <= interval <= 10.5, intervals)
        for db in connections:
            db.start_transaction.assert_called_once()
            db.commit.assert_called_once()
            db.close.assert_called_once()
            db.rollback.assert_not_called()
            calls = db.cursor.return_value.execute.call_args_list
            self.assertEqual(calls[0].args[1], ('Satellite-01',))
            self.assertEqual(calls[1].args[1], (7,))
            self.assertEqual([call.args[1][0] for call in calls[2:]], [10, 11])
        print('Observed timer intervals (seconds):', [round(interval, 3) for interval in intervals])

    def test_failure_rolls_back_and_closes_cursor(self):
        db = batch_connection()
        cursor = db.cursor.return_value
        cursor.execute.side_effect = [None, None, None, mysql.connector.Error(errno=1644)]
        with telemetry.app.app_context(), patch.object(telemetry, 'get_db', return_value=db):
            with self.assertRaises(mysql.connector.Error):
                telemetry.generate_readings('abnormal')
        db.commit.assert_not_called()
        db.rollback.assert_called_once()
        cursor.close.assert_called_once()

    def test_inactive_skips_input_but_allows_discarded_demo(self):
        db = batch_connection('Inactive')
        with telemetry.app.app_context(), patch.object(telemetry, 'get_db', return_value=db):
            self.assertEqual(telemetry.generate_readings(automatic=True), 0)
        self.assertEqual(db.cursor.return_value.execute.call_count, 1)
        db.commit.assert_not_called()
        db = batch_connection('Inactive')
        with telemetry.app.app_context(), patch.object(telemetry, 'get_db', return_value=db):
            self.assertEqual(telemetry.generate_readings('rollback'), 2)
        db.rollback.assert_called_once()
        db.commit.assert_not_called()

    def test_worker_retries_after_error(self):
        succeeded = threading.Event()
        calls = []

        def generate(**kwargs):
            calls.append(kwargs)
            if len(calls) == 1:
                raise mysql.connector.Error(errno=2003)
            succeeded.set()
            return 2

        with patch.object(telemetry, 'SIMULATION_INTERVAL', 0.05), patch.object(telemetry, 'generate_readings', generate):
            telemetry.start_simulator()
            self.assertTrue(succeeded.wait(timeout=2))
            telemetry.stop_simulator()
        self.assertGreaterEqual(len(calls), 2)
        self.assertTrue(all(call == {'automatic': True} for call in calls))

    def test_page_refresh_is_read_only_and_keeps_filters(self):
        with patch.object(telemetry, 'select', return_value=[]) as select, patch.object(telemetry, 'generate_readings') as generate:
            for path in ['/', '/live?sensor_id=10&from_date=2026-10-01&to_date=2026-10-14']:
                response = self.client.get(path)
                self.assertEqual(response.status_code, 200)
            generate.assert_not_called()
            for call in select.call_args_list:
                self.assertIn('c.name = %s', call.args[0])
                self.assertEqual(call.args[1][0], 'Satellite-01')
            reading_call = select.call_args_list[7]
            self.assertEqual(reading_call.args[1][1], 10)
            self.assertEqual(str(reading_call.args[1][3]), '2026-10-15')
        with self.client.get('/static/live.js') as response:
            self.assertEqual(response.status_code, 200)

    def test_mutations_cannot_target_a_second_satellite(self):
        with patch.object(telemetry, 'write', return_value=1) as write:
            self.client.post('/spacecraft/status', data={'status': 'Inactive', 'spacecraft_id': 2})
            self.assertEqual(write.call_args.args[1], ('Inactive', 'Satellite-01'))
            self.client.post('/alerts/acknowledge', data={'alert_id': 5})
            self.assertIn('c.name = %s', write.call_args.args[0])
            self.assertEqual(write.call_args.args[1], (5, 'Satellite-01'))
        self.assertEqual(self.client.get('/simulate').status_code, 405)

    def test_reading_views_keep_filters_and_choose_the_limit(self):
        with patch.object(telemetry, 'select', return_value=[]) as select:
            response = self.client.get('/?sensor_id=10')
            self.assertIn('LIMIT 100', select.call_args_list[2].args[0])
            self.assertIn(b'view=all', response.data)
            self.assertIn(b'Current 100 readings', response.data)
            select.reset_mock()
            response = self.client.get('/?view=all&sensor_id=10')
            self.assertNotIn('LIMIT', select.call_args_list[2].args[0])
            self.assertIn(b'name="view" value="all"', response.data)
            self.assertIn(b'sensor_id=10', response.data)
            self.assertNotIn(b'Automatic input is running', response.data)
            self.assertNotIn(b'Tables updated at', response.data)
            self.assertNotIn(b'Automatic readings stay', response.data)
            self.assertEqual(self.client.get('/?view=unknown').status_code, 400)

    def test_alerts_display_reading_id_and_submit_internal_alert_id(self):
        alert = dict(alert_id=6, reading_id=182, spacecraft_name='Satellite-01',
                     sensor_type='Battery', message='LOW reading: 19.00',
                     recorded_at='2026-10-14 22:17:32', acknowledged=False)
        with patch.object(telemetry, 'select', side_effect=[[], [], [], [alert], []]):
            html = self.client.get('/').get_data(as_text=True)
        alerts = html.split('<section id="alerts">')[1].split('</section>')[0]
        self.assertIn('<th>Reading ID</th>', alerts)
        self.assertIn('<td>182</td>', alerts)
        self.assertNotIn('<td>6</td>', alerts)
        self.assertIn('name="alert_id" value="6"', alerts)

    def test_ajax_acknowledgement_returns_json_without_redirect(self):
        headers = {'Accept': 'application/json'}
        with patch.object(telemetry, 'write', return_value=1):
            response = self.client.post('/alerts/acknowledge', data={'alert_id': 6}, headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['success'])
        self.assertNotIn('Location', response.headers)
        with patch.object(telemetry, 'write', return_value=0):
            response = self.client.post('/alerts/acknowledge', data={'alert_id': 6}, headers=headers)
        self.assertEqual(response.status_code, 404)
        self.assertFalse(response.json['success'])
        response = self.client.post('/alerts/acknowledge', data={'alert_id': 'invalid'}, headers=headers)
        self.assertEqual(response.status_code, 400)
        self.assertFalse(response.json['success'])
        with patch.object(telemetry, 'write', side_effect=mysql.connector.Error(errno=2003)):
            response = self.client.post('/alerts/acknowledge', data={'alert_id': 6}, headers=headers)
        self.assertEqual(response.status_code, 503)
        self.assertFalse(response.json['success'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
