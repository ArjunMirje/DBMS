-- ============================================================================
-- ALL MYSQL CODE USED IN THE SPACE TELEMETRY PROJECT
-- ============================================================================
-- STUDY / REFERENCE FILE ONLY.
--
-- This file collects every SQL script currently present in the project.
-- The sections document different stages and purposes, so DO NOT execute this
-- whole file from top to bottom. For a fresh database, use SECTION 1 only.
-- SECTION 2 contains read-only study queries. SECTIONS 3 and 4 are alternative
-- upgrade paths for older databases. SECTION 5 is retained as project history.
-- ============================================================================


-- ============================================================================
-- SECTION 1 - CURRENT COMPLETE SCHEMA (database/schema.sql)
-- ============================================================================

CREATE DATABASE space_telemetry CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE space_telemetry;

CREATE TABLE missions (
    mission_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    purpose VARCHAR(200) NOT NULL,
    start_date DATE NOT NULL
) ENGINE=InnoDB;

CREATE TABLE spacecraft (
    spacecraft_id INT AUTO_INCREMENT PRIMARY KEY,
    mission_id INT NOT NULL,
    name VARCHAR(80) NOT NULL UNIQUE,
    status VARCHAR(10) NOT NULL DEFAULT 'Active',
    orbit_state VARCHAR(10) NOT NULL DEFAULT 'Sunlight',
    contact_state VARCHAR(20) NOT NULL DEFAULT 'Ground contact',
    simulation_step INT NOT NULL DEFAULT 0,
    FOREIGN KEY (mission_id) REFERENCES missions(mission_id),
    CONSTRAINT chk_spacecraft_status CHECK (status IN ('Active', 'Inactive')),
    CONSTRAINT chk_orbit_state CHECK (orbit_state IN ('Sunlight', 'Eclipse')),
    CONSTRAINT chk_contact_state CHECK (contact_state IN ('Ground contact', 'No contact'))
) ENGINE=InnoDB;

CREATE TABLE telemetry_parameters (
    parameter_id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(40) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL UNIQUE,
    category VARCHAR(20) NOT NULL,
    unit VARCHAR(12) NOT NULL,
    normal_min DECIMAL(12,2),
    normal_max DECIMAL(12,2),
    critical_min DECIMAL(12,2),
    critical_max DECIMAL(12,2),
    nominal_value DECIMAL(12,2) NOT NULL,
    max_step DECIMAL(12,2) NOT NULL,
    decimal_places TINYINT UNSIGNED NOT NULL DEFAULT 2,
    activity_rule VARCHAR(20) NOT NULL DEFAULT 'Always',
    description VARCHAR(240) NOT NULL,
    CONSTRAINT chk_parameter_category CHECK (
        category IN ('Thermal', 'Power', 'Attitude', 'Computing', 'Communication', 'Payload')
    ),
    CONSTRAINT chk_activity_rule CHECK (
        activity_rule IN ('Always', 'Sunlight', 'Ground contact')
    ),
    CONSTRAINT chk_normal_range CHECK (
        normal_min IS NULL OR normal_max IS NULL OR normal_min < normal_max
    ),
    CONSTRAINT chk_critical_range CHECK (
        critical_min IS NULL OR critical_max IS NULL OR critical_min < critical_max
    ),
    CONSTRAINT chk_lower_limits CHECK (
        critical_min IS NULL OR normal_min IS NULL OR critical_min <= normal_min
    ),
    CONSTRAINT chk_upper_limits CHECK (
        critical_max IS NULL OR normal_max IS NULL OR normal_max <= critical_max
    ),
    CONSTRAINT chk_decimal_places CHECK (decimal_places <= 4),
    CONSTRAINT chk_max_step CHECK (max_step > 0)
) ENGINE=InnoDB;

CREATE TABLE sensors (
    sensor_id INT AUTO_INCREMENT PRIMARY KEY,
    spacecraft_id INT NOT NULL,
    parameter_id INT NOT NULL,
    FOREIGN KEY (spacecraft_id) REFERENCES spacecraft(spacecraft_id),
    FOREIGN KEY (parameter_id) REFERENCES telemetry_parameters(parameter_id),
    UNIQUE (spacecraft_id, parameter_id)
) ENGINE=InnoDB;

CREATE TABLE readings (
    reading_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sensor_id INT NOT NULL,
    measured_value DECIMAL(12,2) NOT NULL,
    expected_active BOOLEAN NOT NULL DEFAULT TRUE,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sensor_id) REFERENCES sensors(sensor_id),
    INDEX idx_sensor_time (sensor_id, recorded_at)
) ENGINE=InnoDB;

CREATE TABLE alerts (
    alert_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    reading_id BIGINT NOT NULL UNIQUE,
    severity VARCHAR(10) NOT NULL,
    message VARCHAR(240) NOT NULL,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (reading_id) REFERENCES readings(reading_id),
    CONSTRAINT chk_alert_severity CHECK (severity IN ('Warning', 'Critical'))
) ENGINE=InnoDB;

DELIMITER $$
CREATE FUNCTION classify_reading (
    p_value DECIMAL(12,2),
    p_normal_min DECIMAL(12,2),
    p_normal_max DECIMAL(12,2),
    p_critical_min DECIMAL(12,2),
    p_critical_max DECIMAL(12,2),
    p_expected_active BOOLEAN
) RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
    IF NOT p_expected_active THEN
        RETURN 'STANDBY';
    ELSEIF (p_critical_min IS NOT NULL AND p_value < p_critical_min)
        OR (p_critical_max IS NOT NULL AND p_value > p_critical_max) THEN
        RETURN 'CRITICAL';
    ELSEIF (p_normal_min IS NOT NULL AND p_value < p_normal_min)
        OR (p_normal_max IS NOT NULL AND p_value > p_normal_max) THEN
        RETURN 'WARNING';
    ELSE
        RETURN 'NORMAL';
    END IF;
END$$

CREATE PROCEDURE add_reading (
    IN p_sensor_id INT,
    IN p_value DECIMAL(12,2),
    IN p_expected_active BOOLEAN
)
BEGIN
    IF p_value IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A reading value is required';
    END IF;
    INSERT INTO readings (sensor_id, measured_value, expected_active)
    VALUES (p_sensor_id, p_value, p_expected_active);
END$$

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

INSERT INTO missions (name, purpose, start_date)
VALUES ('Earth Observation Demo', '6U low-Earth-orbit spacecraft health monitoring', '2026-10-01');

INSERT INTO spacecraft (mission_id, name)
VALUES (1, 'Satellite-01');

INSERT INTO telemetry_parameters
    (code, name, category, unit, normal_min, normal_max, critical_min, critical_max,
     nominal_value, max_step, decimal_places, activity_rule, description)
VALUES
    ('processor_temp', 'Processor temperature', 'Thermal', '°C', 10, 60, -10, 80,
     35, 1.20, 1, 'Always', 'Temperature of the onboard computer processor'),
    ('battery_temp', 'Battery temperature', 'Thermal', '°C', 0, 35, -10, 40,
     20, 0.50, 1, 'Always', 'Temperature of the lithium-ion battery pack'),
    ('payload_temp', 'Payload temperature', 'Thermal', '°C', -20, 40, -30, 50,
     15, 0.80, 1, 'Always', 'Temperature of the Earth-observation payload electronics'),
    ('attitude_error', 'Attitude pointing error', 'Attitude', '°', 0, 0.20, 0, 1.00,
     0.05, 0.03, 2, 'Always', 'Angular difference between commanded and measured pointing'),
    ('battery_charge', 'Battery state of charge', 'Power', '%', 30, 100, 20, 100,
     75, 0.40, 1, 'Always', 'Estimated remaining battery charge'),
    ('battery_voltage', 'Battery voltage', 'Power', 'V', 7.20, 8.30, 6.40, 8.40,
     7.90, 0.04, 2, 'Always', 'Voltage of the two-cell lithium-ion battery'),
    ('power_bus_voltage', 'Regulated power bus', 'Power', 'V', 4.75, 5.25, 4.50, 5.50,
     5.00, 0.03, 2, 'Always', 'Regulated five-volt spacecraft power bus'),
    ('solar_array_current', 'Solar-array current', 'Power', 'A', 0.50, 4.30, 0.10, 4.80,
     2.40, 0.25, 2, 'Sunlight', 'Current produced by the solar array in sunlight'),
    ('battery_current', 'Battery current', 'Power', 'A', -3.50, 0.50, -4.00, 0.75,
     0.20, 0.12, 2, 'Always', 'Negative values discharge the battery and positive values charge it'),
    ('computer_reset_count', 'Computer resets in current orbit', 'Computing', 'resets', 0, 0.50, 0, 2,
     0, 1.00, 0, 'Always', 'Watchdog or unexpected onboard-computer resets during the current orbit'),
    ('reaction_wheel_speed', 'Reaction-wheel speed', 'Attitude', 'rpm', -4000, 4000, -5000, 5000,
     1500, 220, 0, 'Always', 'Speed of the primary attitude-control reaction wheel'),
    ('angular_rate', 'Spacecraft angular rate', 'Attitude', '°/s', -0.50, 0.50, -1.00, 1.00,
     0, 0.08, 2, 'Always', 'Rotation rate while the spacecraft is in nominal pointing mode'),
    ('storage_used', 'Onboard storage used', 'Computing', '%', 0, 80, 0, 95,
     45, 0.30, 1, 'Always', 'Percentage of the science-data recorder currently occupied'),
    ('payload_status', 'Payload operational status', 'Payload', '', 1, 3, 1, 3,
     2, 1.00, 0, 'Always', 'Camera status code: fault, idle, ready, or imaging'),
    ('communication_link_health', 'Communication-link health', 'Communication', '%', 90, 100, 70, 100,
     98, 2.00, 1, 'Ground contact', 'Combined receiver-lock and valid-packet health during contact');

INSERT INTO sensors (spacecraft_id, parameter_id)
SELECT 1, parameter_id FROM telemetry_parameters ORDER BY parameter_id;

INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE s.spacecraft_id = 1;


-- ============================================================================
-- SECTION 2 - DBMS REVIEW AND STUDY QUERIES (database/review_queries.sql)
-- ============================================================================

USE space_telemetry;

-- Basic string and date functions.
SELECT UPPER(name) AS mission_name, YEAR(start_date) AS start_year FROM missions;

-- Join the normalized telemetry definitions to their readings.
SELECT r.reading_id, p.name, r.measured_value, p.unit, DATE(r.recorded_at) AS reading_date
FROM readings r
JOIN sensors s ON s.sensor_id = r.sensor_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
ORDER BY r.recorded_at DESC;

-- Aggregate readings by telemetry parameter.
SELECT p.category, p.name, COUNT(*) AS total, ROUND(AVG(r.measured_value), 2) AS average
FROM readings r
JOIN sensors s ON s.sensor_id = r.sensor_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
GROUP BY p.parameter_id, p.category, p.name
HAVING COUNT(*) >= 2;

-- Nested query for parameters that have produced an alert.
SELECT p.parameter_id, p.name
FROM telemetry_parameters p
WHERE p.parameter_id IN (
    SELECT s.parameter_id
    FROM sensors s JOIN readings r ON r.sensor_id = s.sensor_id
    JOIN alerts a ON a.reading_id = r.reading_id
);

-- Set operation across power and thermal parameters.
SELECT name FROM telemetry_parameters WHERE category = 'Power'
UNION
SELECT name FROM telemetry_parameters WHERE category = 'Thermal';

-- Function boundary examples.
SELECT classify_reading(35, 10, 60, -10, 80, TRUE) AS normal_state;
SELECT classify_reading(70, 10, 60, -10, 80, TRUE) AS warning_state;
SELECT classify_reading(90, 10, 60, -10, 80, TRUE) AS critical_state;
SELECT classify_reading(0, 0.5, 4.3, 0.1, 4.8, FALSE) AS standby_state;

-- Index and query-plan demonstration.
SHOW INDEX FROM readings;
EXPLAIN SELECT * FROM readings
WHERE sensor_id = 1 AND recorded_at >= '2026-10-01 00:00:00';


-- ============================================================================
-- SECTION 3 - MIGRATION FROM ORIGINAL TWO-SENSOR DATABASE (database/migrate_v2.sql)
-- ============================================================================

-- Run this once only on a database created by the original two-sensor schema.
USE space_telemetry;
SET @previous_sql_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;

DROP TRIGGER create_reading_alert;
DROP PROCEDURE add_reading;
DROP FUNCTION classify_reading;

ALTER TABLE spacecraft
    ADD COLUMN orbit_state VARCHAR(10) NOT NULL DEFAULT 'Sunlight',
    ADD COLUMN contact_state VARCHAR(20) NOT NULL DEFAULT 'Ground contact',
    ADD COLUMN simulation_step INT NOT NULL DEFAULT 0,
    ADD CONSTRAINT chk_orbit_state CHECK (orbit_state IN ('Sunlight', 'Eclipse')),
    ADD CONSTRAINT chk_contact_state CHECK (contact_state IN ('Ground contact', 'No contact'));

CREATE TABLE telemetry_parameters (
    parameter_id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(40) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL UNIQUE,
    category VARCHAR(20) NOT NULL,
    unit VARCHAR(12) NOT NULL,
    normal_min DECIMAL(12,2),
    normal_max DECIMAL(12,2),
    critical_min DECIMAL(12,2),
    critical_max DECIMAL(12,2),
    nominal_value DECIMAL(12,2) NOT NULL,
    max_step DECIMAL(12,2) NOT NULL,
    decimal_places TINYINT UNSIGNED NOT NULL DEFAULT 2,
    activity_rule VARCHAR(20) NOT NULL DEFAULT 'Always',
    description VARCHAR(240) NOT NULL,
    CONSTRAINT chk_parameter_category CHECK (category IN ('Thermal', 'Power', 'Attitude', 'Computing', 'Communication', 'Payload')),
    CONSTRAINT chk_activity_rule CHECK (activity_rule IN ('Always', 'Sunlight', 'Ground contact')),
    CONSTRAINT chk_normal_range CHECK (normal_min IS NULL OR normal_max IS NULL OR normal_min < normal_max),
    CONSTRAINT chk_critical_range CHECK (critical_min IS NULL OR critical_max IS NULL OR critical_min < critical_max),
    CONSTRAINT chk_lower_limits CHECK (critical_min IS NULL OR normal_min IS NULL OR critical_min <= normal_min),
    CONSTRAINT chk_upper_limits CHECK (critical_max IS NULL OR normal_max IS NULL OR normal_max <= critical_max),
    CONSTRAINT chk_decimal_places CHECK (decimal_places <= 4),
    CONSTRAINT chk_max_step CHECK (max_step > 0)
) ENGINE=InnoDB;

INSERT INTO telemetry_parameters
    (code, name, category, unit, normal_min, normal_max, critical_min, critical_max,
     nominal_value, max_step, decimal_places, activity_rule, description)
VALUES
    ('processor_temp', 'Processor temperature', 'Thermal', '°C', 10, 60, -10, 80, 35, 1.20, 1, 'Always', 'Temperature of the onboard computer processor'),
    ('battery_temp', 'Battery temperature', 'Thermal', '°C', 0, 35, -10, 40, 20, 0.50, 1, 'Always', 'Temperature of the lithium-ion battery pack'),
    ('payload_temp', 'Payload temperature', 'Thermal', '°C', -20, 40, -30, 50, 15, 0.80, 1, 'Always', 'Temperature of the Earth-observation payload electronics'),
    ('attitude_error', 'Attitude pointing error', 'Attitude', '°', 0, 0.20, 0, 1.00, 0.05, 0.03, 2, 'Always', 'Angular difference between commanded and measured pointing'),
    ('battery_charge', 'Battery state of charge', 'Power', '%', 30, 100, 20, 100, 75, 0.40, 1, 'Always', 'Estimated remaining battery charge'),
    ('battery_voltage', 'Battery voltage', 'Power', 'V', 7.20, 8.30, 6.40, 8.40, 7.90, 0.04, 2, 'Always', 'Voltage of the two-cell lithium-ion battery'),
    ('power_bus_voltage', 'Regulated power bus', 'Power', 'V', 4.75, 5.25, 4.50, 5.50, 5.00, 0.03, 2, 'Always', 'Regulated five-volt spacecraft power bus'),
    ('solar_array_current', 'Solar-array current', 'Power', 'A', 0.50, 4.30, 0.10, 4.80, 2.40, 0.25, 2, 'Sunlight', 'Current produced by the solar array in sunlight'),
    ('battery_current', 'Battery current', 'Power', 'A', -3.50, 0.50, -4.00, 0.75, 0.20, 0.12, 2, 'Always', 'Negative values discharge the battery and positive values charge it'),
    ('computer_reset_count', 'Computer resets in current orbit', 'Computing', 'resets', 0, 0.50, 0, 2, 0, 1.00, 0, 'Always', 'Watchdog or unexpected onboard-computer resets during the current orbit'),
    ('reaction_wheel_speed', 'Reaction-wheel speed', 'Attitude', 'rpm', -4000, 4000, -5000, 5000, 1500, 220, 0, 'Always', 'Speed of the primary attitude-control reaction wheel'),
    ('angular_rate', 'Spacecraft angular rate', 'Attitude', '°/s', -0.50, 0.50, -1.00, 1.00, 0, 0.08, 2, 'Always', 'Rotation rate while the spacecraft is in nominal pointing mode'),
    ('storage_used', 'Onboard storage used', 'Computing', '%', 0, 80, 0, 95, 45, 0.30, 1, 'Always', 'Percentage of the science-data recorder currently occupied'),
    ('payload_status', 'Payload operational status', 'Payload', '', 1, 3, 1, 3, 2, 1.00, 0, 'Always', 'Camera status code: fault, idle, ready, or imaging'),
    ('communication_link_health', 'Communication-link health', 'Communication', '%', 90, 100, 70, 100, 98, 2.00, 1, 'Ground contact', 'Combined receiver-lock and valid-packet health during contact');

ALTER TABLE sensors
    DROP CHECK sensors_chk_1,
    DROP CHECK sensors_chk_2,
    DROP CHECK sensors_chk_3,
    ADD COLUMN parameter_id INT NULL,
    ADD INDEX idx_sensor_spacecraft (spacecraft_id);

UPDATE sensors s
JOIN telemetry_parameters p
  ON p.code = CASE s.sensor_type
      WHEN 'Temperature' THEN 'processor_temp'
      WHEN 'Battery' THEN 'battery_charge'
  END
SET s.parameter_id = p.parameter_id
WHERE s.sensor_id > 0;

INSERT INTO sensors (spacecraft_id, sensor_type, min_value, max_value, parameter_id)
SELECT c.spacecraft_id, CONCAT('parameter_', p.parameter_id),
       COALESCE(p.normal_min, -999999), COALESCE(p.normal_max, 999999), p.parameter_id
FROM spacecraft c
CROSS JOIN telemetry_parameters p
WHERE c.name = 'Satellite-01'
  AND NOT EXISTS (
      SELECT 1 FROM sensors existing
      WHERE existing.spacecraft_id = c.spacecraft_id AND existing.parameter_id = p.parameter_id
  );

ALTER TABLE sensors
    MODIFY parameter_id INT NOT NULL,
    ADD CONSTRAINT fk_sensor_parameter FOREIGN KEY (parameter_id) REFERENCES telemetry_parameters(parameter_id),
    ADD CONSTRAINT uq_spacecraft_parameter UNIQUE (spacecraft_id, parameter_id),
    DROP INDEX spacecraft_id,
    DROP COLUMN sensor_type,
    DROP COLUMN min_value,
    DROP COLUMN max_value;

ALTER TABLE readings
    ADD COLUMN expected_active BOOLEAN NOT NULL DEFAULT TRUE AFTER measured_value;

ALTER TABLE alerts
    ADD COLUMN severity VARCHAR(10) NOT NULL DEFAULT 'Warning' AFTER reading_id;

DELIMITER $$
CREATE FUNCTION classify_reading (
    p_value DECIMAL(12,2), p_normal_min DECIMAL(12,2), p_normal_max DECIMAL(12,2),
    p_critical_min DECIMAL(12,2), p_critical_max DECIMAL(12,2), p_expected_active BOOLEAN
) RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
    IF NOT p_expected_active THEN RETURN 'STANDBY';
    ELSEIF (p_critical_min IS NOT NULL AND p_value < p_critical_min)
        OR (p_critical_max IS NOT NULL AND p_value > p_critical_max) THEN RETURN 'CRITICAL';
    ELSEIF (p_normal_min IS NOT NULL AND p_value < p_normal_min)
        OR (p_normal_max IS NOT NULL AND p_value > p_normal_max) THEN RETURN 'WARNING';
    ELSE RETURN 'NORMAL';
    END IF;
END$$

CREATE PROCEDURE add_reading (IN p_sensor_id INT, IN p_value DECIMAL(12,2), IN p_expected_active BOOLEAN)
BEGIN
    IF p_value IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A reading value is required'; END IF;
    INSERT INTO readings (sensor_id, measured_value, expected_active)
    VALUES (p_sensor_id, p_value, p_expected_active);
END$$

CREATE TRIGGER create_reading_alert AFTER INSERT ON readings FOR EACH ROW
BEGIN
    DECLARE v_code VARCHAR(40); DECLARE v_name VARCHAR(80); DECLARE v_unit VARCHAR(12);
    DECLARE v_normal_min DECIMAL(12,2); DECLARE v_normal_max DECIMAL(12,2);
    DECLARE v_critical_min DECIMAL(12,2); DECLARE v_critical_max DECIMAL(12,2);
    DECLARE v_state VARCHAR(10);
    SELECT p.code, p.name, p.unit, p.normal_min, p.normal_max, p.critical_min, p.critical_max
      INTO v_code, v_name, v_unit, v_normal_min, v_normal_max, v_critical_min, v_critical_max
    FROM sensors s JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
    WHERE s.sensor_id = NEW.sensor_id;
    SET v_state = classify_reading(NEW.measured_value, v_normal_min, v_normal_max,
                                   v_critical_min, v_critical_max, NEW.expected_active);
    IF v_state IN ('WARNING', 'CRITICAL') THEN
        INSERT INTO alerts (reading_id, severity, message)
        VALUES (NEW.reading_id, CONCAT(UPPER(LEFT(v_state, 1)), LOWER(SUBSTRING(v_state, 2))),
                CASE WHEN v_code = 'payload_status' THEN CONCAT(v_name, ' reported FAULT')
                     ELSE CONCAT(v_name, ' is ', NEW.measured_value, ' ', v_unit) END);
    END IF;
END$$
DELIMITER ;

UPDATE alerts a
JOIN readings r ON r.reading_id = a.reading_id
JOIN sensors s ON s.sensor_id = r.sensor_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
SET a.severity = CASE
    WHEN classify_reading(r.measured_value, p.normal_min, p.normal_max,
                          p.critical_min, p.critical_max, r.expected_active) = 'CRITICAL'
    THEN 'Critical' ELSE 'Warning' END
WHERE a.alert_id > 0;

ALTER TABLE alerts
    ADD CONSTRAINT chk_alert_severity CHECK (severity IN ('Warning', 'Critical'));

INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE c.name = 'Satellite-01'
  AND NOT EXISTS (SELECT 1 FROM readings r WHERE r.sensor_id = s.sensor_id);

SET SQL_SAFE_UPDATES = @previous_sql_safe_updates;


-- ============================================================================
-- SECTION 4 - MIGRATION FROM EARLIER 15-PARAMETER DATABASE (database/migrate_v3_diagnostics.sql)
-- ============================================================================

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


-- ============================================================================
-- SECTION 5 - HISTORICAL EARLIER SCHEMA COPY (project.sql)
-- ============================================================================

CREATE DATABASE space_telemetry CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE space_telemetry;

CREATE TABLE missions (
    mission_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    purpose VARCHAR(200) NOT NULL,
    start_date DATE NOT NULL
) ENGINE=InnoDB;

CREATE TABLE spacecraft (
    spacecraft_id INT AUTO_INCREMENT PRIMARY KEY,
    mission_id INT NOT NULL,
    name VARCHAR(80) NOT NULL UNIQUE,
    status VARCHAR(10) NOT NULL DEFAULT 'Active',
    orbit_state VARCHAR(10) NOT NULL DEFAULT 'Sunlight',
    contact_state VARCHAR(20) NOT NULL DEFAULT 'Ground contact',
    simulation_step INT NOT NULL DEFAULT 0,
    FOREIGN KEY (mission_id) REFERENCES missions(mission_id),
    CONSTRAINT chk_spacecraft_status CHECK (status IN ('Active', 'Inactive')),
    CONSTRAINT chk_orbit_state CHECK (orbit_state IN ('Sunlight', 'Eclipse')),
    CONSTRAINT chk_contact_state CHECK (contact_state IN ('Ground contact', 'No contact'))
) ENGINE=InnoDB;

CREATE TABLE telemetry_parameters (
    parameter_id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(40) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL UNIQUE,
    category VARCHAR(20) NOT NULL,
    unit VARCHAR(12) NOT NULL,
    normal_min DECIMAL(12,2),
    normal_max DECIMAL(12,2),
    critical_min DECIMAL(12,2),
    critical_max DECIMAL(12,2),
    nominal_value DECIMAL(12,2) NOT NULL,
    max_step DECIMAL(12,2) NOT NULL,
    decimal_places TINYINT UNSIGNED NOT NULL DEFAULT 2,
    activity_rule VARCHAR(20) NOT NULL DEFAULT 'Always',
    description VARCHAR(240) NOT NULL,
    CONSTRAINT chk_parameter_category CHECK (
        category IN ('Thermal', 'Power', 'Attitude', 'Computing', 'Communication')
    ),
    CONSTRAINT chk_activity_rule CHECK (
        activity_rule IN ('Always', 'Sunlight', 'Ground contact')
    ),
    CONSTRAINT chk_normal_range CHECK (
        normal_min IS NULL OR normal_max IS NULL OR normal_min < normal_max
    ),
    CONSTRAINT chk_critical_range CHECK (
        critical_min IS NULL OR critical_max IS NULL OR critical_min < critical_max
    ),
    CONSTRAINT chk_lower_limits CHECK (
        critical_min IS NULL OR normal_min IS NULL OR critical_min <= normal_min
    ),
    CONSTRAINT chk_upper_limits CHECK (
        critical_max IS NULL OR normal_max IS NULL OR normal_max <= critical_max
    ),
    CONSTRAINT chk_decimal_places CHECK (decimal_places <= 4),
    CONSTRAINT chk_max_step CHECK (max_step > 0)
) ENGINE=InnoDB;

CREATE TABLE sensors (
    sensor_id INT AUTO_INCREMENT PRIMARY KEY,
    spacecraft_id INT NOT NULL,
    parameter_id INT NOT NULL,
    FOREIGN KEY (spacecraft_id) REFERENCES spacecraft(spacecraft_id),
    FOREIGN KEY (parameter_id) REFERENCES telemetry_parameters(parameter_id),
    UNIQUE (spacecraft_id, parameter_id)
) ENGINE=InnoDB;

CREATE TABLE readings (
    reading_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sensor_id INT NOT NULL,
    measured_value DECIMAL(12,2) NOT NULL,
    expected_active BOOLEAN NOT NULL DEFAULT TRUE,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sensor_id) REFERENCES sensors(sensor_id),
    INDEX idx_sensor_time (sensor_id, recorded_at)
) ENGINE=InnoDB;

CREATE TABLE alerts (
    alert_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    reading_id BIGINT NOT NULL UNIQUE,
    severity VARCHAR(10) NOT NULL,
    message VARCHAR(240) NOT NULL,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (reading_id) REFERENCES readings(reading_id),
    CONSTRAINT chk_alert_severity CHECK (severity IN ('Warning', 'Critical'))
) ENGINE=InnoDB;

DELIMITER $$
CREATE FUNCTION classify_reading (
    p_value DECIMAL(12,2),
    p_normal_min DECIMAL(12,2),
    p_normal_max DECIMAL(12,2),
    p_critical_min DECIMAL(12,2),
    p_critical_max DECIMAL(12,2),
    p_expected_active BOOLEAN
) RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
    IF NOT p_expected_active THEN
        RETURN 'STANDBY';
    ELSEIF (p_critical_min IS NOT NULL AND p_value < p_critical_min)
        OR (p_critical_max IS NOT NULL AND p_value > p_critical_max) THEN
        RETURN 'CRITICAL';
    ELSEIF (p_normal_min IS NOT NULL AND p_value < p_normal_min)
        OR (p_normal_max IS NOT NULL AND p_value > p_normal_max) THEN
        RETURN 'WARNING';
    ELSE
        RETURN 'NORMAL';
    END IF;
END$$

CREATE PROCEDURE add_reading (
    IN p_sensor_id INT,
    IN p_value DECIMAL(12,2),
    IN p_expected_active BOOLEAN
)
BEGIN
    IF p_value IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A reading value is required';
    END IF;
    INSERT INTO readings (sensor_id, measured_value, expected_active)
    VALUES (p_sensor_id, p_value, p_expected_active);
END$$

CREATE TRIGGER create_reading_alert
AFTER INSERT ON readings
FOR EACH ROW
BEGIN
    DECLARE v_name VARCHAR(80);
    DECLARE v_unit VARCHAR(12);
    DECLARE v_normal_min DECIMAL(12,2);
    DECLARE v_normal_max DECIMAL(12,2);
    DECLARE v_critical_min DECIMAL(12,2);
    DECLARE v_critical_max DECIMAL(12,2);
    DECLARE v_state VARCHAR(10);

    SELECT p.name, p.unit, p.normal_min, p.normal_max, p.critical_min, p.critical_max
    INTO v_name, v_unit, v_normal_min, v_normal_max, v_critical_min, v_critical_max
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
            CONCAT(v_name, ' is ', NEW.measured_value, ' ', v_unit)
        );
    END IF;
END$$
DELIMITER ;

INSERT INTO missions (name, purpose, start_date)
VALUES ('Earth Observation Demo', '6U low-Earth-orbit spacecraft health monitoring', '2026-10-01');

INSERT INTO spacecraft (mission_id, name)
VALUES (1, 'Satellite-01');

INSERT INTO telemetry_parameters
    (code, name, category, unit, normal_min, normal_max, critical_min, critical_max,
     nominal_value, max_step, decimal_places, activity_rule, description)
VALUES
    ('processor_temp', 'Processor temperature', 'Thermal', '°C', 10, 60, -10, 80,
     35, 1.20, 1, 'Always', 'Temperature of the onboard computer processor'),
    ('battery_temp', 'Battery temperature', 'Thermal', '°C', 0, 35, -10, 40,
     20, 0.50, 1, 'Always', 'Temperature of the lithium-ion battery pack'),
    ('payload_temp', 'Payload temperature', 'Thermal', '°C', -20, 40, -30, 50,
     15, 0.80, 1, 'Always', 'Temperature of the Earth-observation payload electronics'),
    ('solar_panel_temp', 'Solar-panel temperature', 'Thermal', '°C', -50, 55, -75, 70,
     10, 3.00, 1, 'Always', 'Temperature measured on a solar-array panel'),
    ('battery_charge', 'Battery state of charge', 'Power', '%', 30, 100, 20, 100,
     75, 0.40, 1, 'Always', 'Estimated remaining battery charge'),
    ('battery_voltage', 'Battery voltage', 'Power', 'V', 7.20, 8.30, 6.40, 8.40,
     7.90, 0.04, 2, 'Always', 'Voltage of the two-cell lithium-ion battery'),
    ('power_bus_voltage', 'Regulated power bus', 'Power', 'V', 4.75, 5.25, 4.50, 5.50,
     5.00, 0.03, 2, 'Always', 'Regulated five-volt spacecraft power bus'),
    ('solar_array_current', 'Solar-array current', 'Power', 'A', 0.50, 4.30, 0.10, 4.80,
     2.40, 0.25, 2, 'Sunlight', 'Current produced by the solar array in sunlight'),
    ('battery_current', 'Battery current', 'Power', 'A', -3.50, 0.50, -4.00, 0.75,
     0.20, 0.12, 2, 'Always', 'Negative values discharge the battery and positive values charge it'),
    ('power_use', 'Total spacecraft power use', 'Power', 'W', 0, 20, 0, 30,
     12, 0.80, 1, 'Always', 'Combined electrical load of active spacecraft systems'),
    ('reaction_wheel_speed', 'Reaction-wheel speed', 'Attitude', 'rpm', -4000, 4000, -5000, 5000,
     1500, 220, 0, 'Always', 'Speed of the primary attitude-control reaction wheel'),
    ('angular_rate', 'Spacecraft angular rate', 'Attitude', '°/s', -0.50, 0.50, -1.00, 1.00,
     0, 0.08, 2, 'Always', 'Rotation rate while the spacecraft is in nominal pointing mode'),
    ('storage_used', 'Onboard storage used', 'Computing', '%', 0, 80, 0, 95,
     45, 0.30, 1, 'Always', 'Percentage of the science-data recorder currently occupied'),
    ('computer_load', 'Onboard computer load', 'Computing', '%', 0, 80, 0, 95,
     45, 4.00, 1, 'Always', 'Processing load on the main onboard computer'),
    ('radio_signal', 'Radio signal strength', 'Communication', 'dBm', -105, NULL, -115, NULL,
     -85, 3.00, 1, 'Ground contact', 'Received signal strength during a ground-station contact');

INSERT INTO sensors (spacecraft_id, parameter_id)
SELECT 1, parameter_id FROM telemetry_parameters ORDER BY parameter_id;

INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE s.spacecraft_id = 1;


