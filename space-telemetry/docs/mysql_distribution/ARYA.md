# Arya — Alerts and automatic database logic

> These are study notes. The source-line numbers refer to the original SQL files. The migration sections are alternatives for upgrading old databases; they are not run after a fresh schema installation.

## Alerts table

Source: `database/schema.sql`, lines 81-90

```sql
CREATE TABLE alerts (
    alert_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    reading_id BIGINT NOT NULL UNIQUE,
    severity VARCHAR(10) NOT NULL,
    message VARCHAR(240) NOT NULL,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (reading_id) REFERENCES readings(reading_id),
    CONSTRAINT chk_alert_severity CHECK (severity IN ('Warning', 'Critical'))
) ENGINE=InnoDB;

```

### Explanation

- **Lines 81-87:** Create `alerts`. Each alert belongs to exactly one reading, and `UNIQUE` prevents duplicate alerts for that reading.
- **Lines 88-90:** Connect alerts to Sarish's readings and restrict severity to Warning or Critical.

## Automatic alert trigger

Source: `database/schema.sql`, lines 129-164

```sql
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

```

### Explanation

- **Lines 129-132:** Create a trigger that runs after every new reading.
- **Lines 133-140:** Declare local variables for parameter details, boundaries, and the calculated state.
- **Lines 142-146:** Join the new reading's sensor to Arjun's parameter definition and load its code, name, unit, and limits.
- **Lines 148-152:** Call Arjun's `classify_reading` function using the new value and activity flag.
- **Lines 153-158:** Insert an alert only for Warning or Critical states and format the severity with normal capitalization.
- **Lines 159-161:** Use a special human-readable fault message for payload status; other parameters show value and unit.
- **Lines 162-164:** Close the trigger and restore the normal semicolon delimiter.

## Install upgraded routines and alert handling in the legacy migration

Source: `database/migrate_v2.sql`, lines 104-161

```sql
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

```

### Explanation

- **Lines 104-119:** Recreate the classification function with standby, critical, warning, and normal outcomes.
- **Lines 121-127:** Recreate the validated `add_reading` procedure.
- **Lines 129-146:** Recreate the automatic alert trigger against the normalized parameter table.
- **Lines 147-148:** Restore the normal delimiter after routine creation.
- **Lines 149-158:** Recalculate old alerts as Critical or Warning by joining each alert back to its reading, sensor, and parameter boundaries.
- **Lines 159-161:** Add the final severity check after the existing data has been corrected.

## Replace the trigger for the revised diagnostics

Source: `database/migrate_v3_diagnostics.sql`, lines 57-94

```sql
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

```

### Explanation

- **Line 57:** Drop the earlier trigger before installing its replacement.
- **Lines 58-62:** Change the delimiter and begin the new after-insert trigger.
- **Lines 63-70:** Declare variables for the telemetry code, display information, boundaries, and state.
- **Lines 72-76:** Load the matching parameter definition for the sensor that produced the reading.
- **Lines 78-82:** Classify the new value with Arjun's function.
- **Lines 83-91:** Generate an alert only when required, including the special payload-fault wording.
- **Lines 92-94:** Finish the trigger and restore the normal delimiter.

## Connections to the other members

- `alerts.reading_id` points to the reading stored by **Sarish**.
- The trigger starts automatically whenever **Sarish's** table receives a new reading.
- It follows `readings.sensor_id` to Sarish's sensor mapping, then follows `parameter_id` to **Arjun's** telemetry limits.
- It calls **Arjun's** `classify_reading` function to obtain NORMAL, WARNING, CRITICAL, or STANDBY.
- **Aryan's** review queries later join and inspect the alerts produced here.

