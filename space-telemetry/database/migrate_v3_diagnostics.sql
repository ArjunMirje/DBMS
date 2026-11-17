-- Run this once on the earlier 15-parameter version.
USE space_telemetry;
SET @previous_sql_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;

-- Remove readings whose meaning changes with the four replaced definitions.
DELETE a FROM alerts a
JOIN readings r ON r.reading_id = a.reading_id
JOIN sensors s ON s.sensor_id = r.sensor_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE p.code IN ('solar_panel_temp', 'power_use', 'computer_load', 'radio_signal')
  AND a.alert_id > 0;

DELETE r FROM readings r
JOIN sensors s ON s.sensor_id = r.sensor_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE p.code IN ('solar_panel_temp', 'power_use', 'computer_load', 'radio_signal')
  AND r.reading_id > 0;

ALTER TABLE telemetry_parameters DROP CHECK chk_parameter_category;

UPDATE telemetry_parameters
SET code = 'attitude_error', name = 'Attitude pointing error', category = 'Attitude', unit = '°',
    normal_min = 0, normal_max = 0.20, critical_min = 0, critical_max = 1.00,
    nominal_value = 0.05, max_step = 0.03, decimal_places = 2, activity_rule = 'Always',
    description = 'Angular difference between commanded and measured pointing'
WHERE parameter_id > 0 AND code = 'solar_panel_temp';

UPDATE telemetry_parameters
SET code = 'computer_reset_count', name = 'Computer resets in current orbit',
    category = 'Computing', unit = 'resets', normal_min = 0, normal_max = 0.50,
    critical_min = 0, critical_max = 2, nominal_value = 0, max_step = 1,
    decimal_places = 0, activity_rule = 'Always',
    description = 'Watchdog or unexpected onboard-computer resets during the current orbit'
WHERE parameter_id > 0 AND code = 'power_use';

UPDATE telemetry_parameters
SET code = 'payload_status', name = 'Payload operational status', category = 'Payload', unit = '',
    normal_min = 1, normal_max = 3, critical_min = 1, critical_max = 3,
    nominal_value = 2, max_step = 1, decimal_places = 0, activity_rule = 'Always',
    description = 'Camera status code: fault, idle, ready, or imaging'
WHERE parameter_id > 0 AND code = 'computer_load';

UPDATE telemetry_parameters
SET code = 'communication_link_health', name = 'Communication-link health',
    category = 'Communication', unit = '%', normal_min = 90, normal_max = 100,
    critical_min = 70, critical_max = 100, nominal_value = 98, max_step = 2,
    decimal_places = 1, activity_rule = 'Ground contact',
    description = 'Combined receiver-lock and valid-packet health during contact'
WHERE parameter_id > 0 AND code = 'radio_signal';

ALTER TABLE telemetry_parameters
    ADD CONSTRAINT chk_parameter_category CHECK (
        category IN ('Thermal', 'Power', 'Attitude', 'Computing', 'Communication', 'Payload')
    );

DROP TRIGGER create_reading_alert;
DELIMITER $$
CREATE TRIGGER create_reading_alert
AFTER INSERT ON readings
FOR EACH ROW
BEGIN
    DECLARE v_code VARCHAR(40);
    DECLARE v_name VARCHAR(80);
    DECLARE v_unit VARCHAR(12);
    DECLARE v_normal_min DECIMAL(12,2);
    DECLARE v_normal_max DECIMAL(12,2);
    DECLARE v_critical_min DECIMAL(12,2);
    DECLARE v_critical_max DECIMAL(12,2);
    DECLARE v_state VARCHAR(10);

    SELECT p.code, p.name, p.unit, p.normal_min, p.normal_max, p.critical_min, p.critical_max
    INTO v_code, v_name, v_unit, v_normal_min, v_normal_max, v_critical_min, v_critical_max
    FROM sensors s
    JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
    WHERE s.sensor_id = NEW.sensor_id;

    SET v_state = classify_reading(
        NEW.measured_value, v_normal_min, v_normal_max,
        v_critical_min, v_critical_max, NEW.expected_active
    );
    IF v_state IN ('WARNING', 'CRITICAL') THEN
        INSERT INTO alerts (reading_id, severity, message)
        VALUES (
            NEW.reading_id,
            CONCAT(UPPER(LEFT(v_state, 1)), LOWER(SUBSTRING(v_state, 2))),
            CASE WHEN v_code = 'payload_status'
                 THEN CONCAT(v_name, ' reported FAULT')
                 ELSE CONCAT(v_name, ' is ', NEW.measured_value, ' ', v_unit) END
        );
    END IF;
END$$
DELIMITER ;

INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE c.name = 'Satellite-01'
  AND p.code IN ('attitude_error', 'computer_reset_count', 'payload_status', 'communication_link_health');

SET SQL_SAFE_UPDATES = @previous_sql_safe_updates;
