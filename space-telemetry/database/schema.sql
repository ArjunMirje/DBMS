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
