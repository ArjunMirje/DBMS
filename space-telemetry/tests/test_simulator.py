"""Simulator, transaction, filtering, and page checks without live MySQL."""
import configparser
import threading
import time
import unittest
from decimal import Decimal
from unittest.mock import MagicMock, patch

import mysql.connector

import app as telemetry


def parameter(sensor_id, code, name, normal_min, normal_max, critical_min, critical_max,
              nominal, step, rule='Always', places=2):
    return dict(sensor_id=sensor_id, parameter_id=sensor_id, code=code, name=name,
                category='Power', unit='%', normal_min=Decimal(str(normal_min)) if normal_min is not None else None,
                normal_max=Decimal(str(normal_max)) if normal_max is not None else None,
                critical_min=Decimal(str(critical_min)) if critical_min is not None else None,
                critical_max=Decimal(str(critical_max)) if critical_max is not None else None,
                nominal_value=Decimal(str(nominal)), max_step=Decimal(str(step)),
                decimal_places=places, activity_rule=rule, previous_value=Decimal(str(nominal)),
                description='Test parameter')


def batch_connection(status='Active'):
    db = MagicMock()
    cursor = db.cursor.return_value
    cursor.fetchone.return_value = {
        'spacecraft_id': 7, 'status': status, 'orbit_state': 'Sunlight',
        'contact_state': 'Ground contact', 'simulation_step': 0,
    }
    cursor.fetchall.return_value = [
        parameter(10, 'battery_charge', 'Battery state of charge', 30, 100, 20, 100, 75, .4, places=1),
        parameter(11, 'solar_array_current', 'Solar-array current', .5, 4.3, .1, 4.8, 2.4, .25, 'Sunlight'),
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

    def test_timer_uses_one_connection_per_batch_and_one_worker(self):
        config = configparser.ConfigParser()
        config.read_dict({'mysql': {'host': '127.0.0.1', 'port': '3306', 'user': 'test',
                                    'password': '', 'database': 'test'}})
        config.read = MagicMock(return_value=['test-config.ini'])
        connections = []
        third_batch = threading.Event()

        def connect(**settings):
            db = batch_connection()
            connections.append(db)
            if len(connections) == 3:
                third_batch.set()
            return db

        with patch.object(telemetry, 'SIMULATION_INTERVAL', .05), \
             patch.object(telemetry.configparser, 'ConfigParser', return_value=config), \
             patch.object(telemetry.mysql.connector, 'connect', connect), \
             patch.object(telemetry.random, 'random', return_value=.5):
            telemetry.start_simulator()
            worker = telemetry.simulator_thread
            telemetry.start_simulator()
            self.assertIs(telemetry.simulator_thread, worker)
            self.assertTrue(third_batch.wait(timeout=2))
            telemetry.stop_simulator()
        self.assertGreaterEqual(len(connections), 3)
        for db in connections[:3]:
            db.start_transaction.assert_called_once()
            db.commit.assert_called_once()
            db.close.assert_called_once()
            calls = db.cursor.return_value.execute.call_args_list
            self.assertEqual(calls[0].args[1], ('Satellite-01',))
            self.assertEqual(calls[2].args[1], (7,))
            self.assertEqual([call.args[1][0] for call in calls[3:]], [10, 11])

    def test_warning_critical_and_standby_values(self):
        battery = parameter(1, 'battery_charge', 'Battery charge', 30, 100, 20, 100, 75, .4, places=1)
        self.assertEqual(telemetry.fault_value(battery, 'warning'), 25.0)
        self.assertLess(telemetry.fault_value(battery, 'critical'), 20)
        radio = parameter(2, 'communication_link_health', 'Communication link', 90, 100, 70, 100, 98, 2, 'Ground contact', 1)
        craft = {'orbit_state': 'Sunlight', 'contact_state': 'No contact'}
        self.assertFalse(telemetry.expected_active(radio, craft))
        self.assertEqual(telemetry.normal_value(radio, craft), 0)

    def test_failure_rolls_back_and_closes_cursor(self):
        db = batch_connection()
        cursor = db.cursor.return_value
        cursor.execute.side_effect = [None, None, None, mysql.connector.Error(errno=1644)]
        with telemetry.app.app_context(), patch.object(telemetry, 'get_db', return_value=db):
            with self.assertRaises(mysql.connector.Error):
                telemetry.generate_readings('critical')
        db.commit.assert_not_called()
        db.rollback.assert_called_once()
        cursor.close.assert_called_once()

    def test_inactive_skips_automatic_and_rejects_manual_input(self):
        db = batch_connection('Inactive')
        with telemetry.app.app_context(), patch.object(telemetry, 'get_db', return_value=db):
            self.assertEqual(telemetry.generate_readings(automatic=True), 0)
        self.assertEqual(db.cursor.return_value.execute.call_count, 1)
        db.commit.assert_not_called()
        db = batch_connection('Inactive')
        with telemetry.app.app_context(), patch.object(telemetry, 'get_db', return_value=db):
            with self.assertRaises(ValueError):
                telemetry.generate_readings('normal')
        db.rollback.assert_called_once()
        db.commit.assert_not_called()

    def test_worker_retries_after_database_error(self):
        succeeded = threading.Event()
        calls = []

        def generate(**kwargs):
            calls.append(kwargs)
            if len(calls) == 1:
                raise mysql.connector.Error(errno=2003)
            succeeded.set()
            return 15

        with patch.object(telemetry, 'SIMULATION_INTERVAL', .05), \
             patch.object(telemetry, 'generate_readings', generate):
            telemetry.start_simulator()
            self.assertTrue(succeeded.wait(timeout=2))
            telemetry.stop_simulator()
        self.assertGreaterEqual(len(calls), 2)
        self.assertTrue(all(call == {'automatic': True} for call in calls))

    def test_page_refresh_is_read_only_and_keeps_filters(self):
        with patch.object(telemetry, 'select', return_value=[]) as select, \
             patch.object(telemetry, 'generate_readings') as generate:
            for path in ['/', '/live?sensor_id=10&category=Power&state=NORMAL&from_date=2026-10-01&to_date=2026-10-14']:
                response = self.client.get(path)
                self.assertEqual(response.status_code, 200)
            generate.assert_not_called()
            reading_call = select.call_args_list[9]
            self.assertIn('filtered_readings', reading_call.args[0])
            self.assertEqual(reading_call.args[1][1], 10)
            self.assertEqual(str(reading_call.args[1][4]), '2026-10-15')
            self.assertEqual(reading_call.args[1][-1], 'NORMAL')
        self.assertEqual(self.client.get('/?state=unknown').status_code, 400)

    def test_mutations_are_limited_to_satellite_01(self):
        with patch.object(telemetry, 'write', return_value=1) as write:
            self.client.post('/spacecraft/status', data={'status': 'Inactive', 'spacecraft_id': 2})
            self.assertEqual(write.call_args.args[1], ('Inactive', 'Satellite-01'))
            self.client.post('/alerts/acknowledge', data={'alert_id': 5})
            self.assertIn('c.name = %s', write.call_args.args[0])
            self.assertEqual(write.call_args.args[1], (5, 'Satellite-01'))
        self.assertEqual(self.client.get('/simulate').status_code, 405)

    def test_ajax_acknowledgement_returns_json_without_redirect(self):
        headers = {'Accept': 'application/json'}
        with patch.object(telemetry, 'write', return_value=1):
            response = self.client.post('/alerts/acknowledge', data={'alert_id': 6}, headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['success'])
        with patch.object(telemetry, 'write', return_value=0):
            response = self.client.post('/alerts/acknowledge', data={'alert_id': 6}, headers=headers)
        self.assertEqual(response.status_code, 404)
        response = self.client.post('/alerts/acknowledge', data={'alert_id': 'invalid'}, headers=headers)
        self.assertEqual(response.status_code, 400)


if __name__ == '__main__':
    unittest.main(verbosity=2)
