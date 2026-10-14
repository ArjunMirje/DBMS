CREATE DATABASE space_telemetry CHARACTER SET utf8mb4;
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
    FOREIGN KEY (mission_id) REFERENCES missions(mission_id),
    CHECK (status IN ('Active', 'Inactive'))
) ENGINE=InnoDB;

CREATE TABLE sensors (
    sensor_id INT AUTO_INCREMENT PRIMARY KEY,
    spacecraft_id INT NOT NULL,
    sensor_type VARCHAR(20) NOT NULL,
    min_value DECIMAL(10,2) NOT NULL,
    max_value DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (spacecraft_id) REFERENCES spacecraft(spacecraft_id),
    UNIQUE (spacecraft_id, sensor_type),
    CHECK (sensor_type IN ('Temperature', 'Battery')),
    CHECK (min_value < max_value),
    CHECK (sensor_type <> 'Battery' OR (min_value >= 0 AND max_value <= 100))
) ENGINE=InnoDB;

CREATE TABLE readings (
    reading_id INT AUTO_INCREMENT PRIMARY KEY,
    sensor_id INT NOT NULL,
    measured_value DECIMAL(10,2) NOT NULL,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sensor_id) REFERENCES sensors(sensor_id),
    INDEX idx_sensor_time (sensor_id, recorded_at)
) ENGINE=InnoDB;

CREATE TABLE alerts (
    alert_id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL UNIQUE,
    message VARCHAR(200) NOT NULL,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (reading_id) REFERENCES readings(reading_id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE FUNCTION classify_reading (
    p_value DECIMAL(10,2), p_min DECIMAL(10,2), p_max DECIMAL(10,2)
) RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
    IF p_value < p_min THEN
        RETURN 'LOW';
    ELSEIF p_value > p_max THEN
        RETURN 'HIGH';
    ELSE
        RETURN 'NORMAL';
    END IF;
END$$

CREATE PROCEDURE add_reading (
    IN p_sensor_id INT, IN p_value DECIMAL(10,2)
)
BEGIN
    IF p_value IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A reading value is required';
    END IF;
    INSERT INTO readings (sensor_id, measured_value)
    VALUES (p_sensor_id, p_value);
END$$

CREATE TRIGGER create_reading_alert
AFTER INSERT ON readings
FOR EACH ROW
BEGIN
    DECLARE v_min DECIMAL(10,2);
    DECLARE v_max DECIMAL(10,2);
    DECLARE v_state VARCHAR(10);
    SELECT min_value, max_value INTO v_min, v_max
    FROM sensors WHERE sensor_id = NEW.sensor_id;
    SET v_state = classify_reading(NEW.measured_value, v_min, v_max);
    IF v_state <> 'NORMAL' THEN
        INSERT INTO alerts (reading_id, message)
        VALUES (NEW.reading_id, CONCAT(v_state, ' reading: ', NEW.measured_value));
    END IF;
END$$
DELIMITER ;

INSERT INTO missions (name, purpose, start_date)
VALUES ('Earth Observation Demo', 'Simulated spacecraft health monitoring', '2026-10-01');
INSERT INTO spacecraft (mission_id, name)
VALUES (1, 'Satellite-01');
INSERT INTO sensors (spacecraft_id, sensor_type, min_value, max_value)
VALUES (1, 'Temperature', -10, 60), (1, 'Battery', 20, 100);

START TRANSACTION;
CALL add_reading(1, 32);
CALL add_reading(2, 85);
COMMIT;