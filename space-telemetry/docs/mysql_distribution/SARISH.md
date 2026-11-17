# Sarish — Sensors, readings, and data migration

> These are study notes. The source-line numbers refer to the original SQL files. The migration sections are alternatives for upgrading old databases; they are not run after a fresh schema installation.

## Sensor and reading tables

Source: `database/schema.sql`, lines 62-80

```sql
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

```

### Explanation

- **Lines 62-68:** Create `sensors`. Each row connects one spacecraft to one telemetry parameter through two foreign keys.
- **Line 68:** The unique constraint prevents the same spacecraft from receiving the same parameter twice.
- **Lines 71-78:** Create `readings` with the measured number, whether the sensor is expected to be active, and an automatic timestamp.
- **Line 79:** Create a combined sensor/time index so recent-history searches remain fast.

## Create sensors and initial readings

Source: `database/schema.sql`, lines 206-213

```sql
INSERT INTO sensors (spacecraft_id, parameter_id)
SELECT 1, parameter_id FROM telemetry_parameters ORDER BY parameter_id;

INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE s.spacecraft_id = 1;
```

### Explanation

- **Lines 206-207:** Create one sensor for every parameter inserted by Aryan, all belonging to spacecraft 1.
- **Lines 209-213:** Join sensors to Arjun's parameter definitions and insert each parameter's nominal value as its first reading.

## Convert old sensors and readings

Source: `database/migrate_v2.sql`, lines 62-103

```sql
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

```

### Explanation

- **Lines 62-67:** Prepare the old `sensors` table by removing old range checks, adding `parameter_id`, and indexing the spacecraft key.
- **Lines 69-76:** Map the two original sensor names—Temperature and Battery—to the new parameter codes. The key-based `WHERE` also satisfies safe-update rules.
- **Lines 78-88:** Create missing sensor rows for every new telemetry definition while `NOT EXISTS` prevents duplicates.
- **Lines 89-96:** Make `parameter_id` compulsory, add its foreign key and unique constraint, then remove obsolete columns.
- **Lines 98-99:** Add `expected_active` to readings so sunlight/contact-dependent parameters can enter standby.
- **Lines 101-103:** Add alert severity in preparation for Arya's upgraded alert logic.

## Give newly added sensors an initial reading

Source: `database/migrate_v2.sql`, lines 162-170

```sql
INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE c.name = 'Satellite-01'
  AND NOT EXISTS (SELECT 1 FROM readings r WHERE r.sensor_id = s.sensor_id);

SET SQL_SAFE_UPDATES = @previous_sql_safe_updates;
```

### Explanation

- **Lines 162-168:** Insert a nominal reading only for sensors that do not already have readings. The joins locate the satellite and its parameter defaults.
- **Line 170:** Restore the user's original safe-update setting.

## Remove readings whose old meaning changed

Source: `database/migrate_v3_diagnostics.sql`, lines 1-19

```sql
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

```

### Explanation

- **Lines 1-4:** Select the database and temporarily disable safe-update mode while remembering its previous value.
- **Lines 6-12:** Delete alerts belonging to the four replaced parameter definitions. Alerts must be deleted first because they reference readings.
- **Lines 14-19:** Delete the corresponding old readings after their dependent alerts are gone.

## Seed the four replacement diagnostics

Source: `database/migrate_v3_diagnostics.sql`, lines 95-103

```sql
INSERT INTO readings (sensor_id, measured_value, expected_active)
SELECT s.sensor_id, p.nominal_value, TRUE
FROM sensors s
JOIN spacecraft c ON c.spacecraft_id = s.spacecraft_id
JOIN telemetry_parameters p ON p.parameter_id = s.parameter_id
WHERE c.name = 'Satellite-01'
  AND p.code IN ('attitude_error', 'computer_reset_count', 'payload_status', 'communication_link_health');

SET SQL_SAFE_UPDATES = @previous_sql_safe_updates;
```

### Explanation

- **Lines 95-101:** Insert nominal readings for the four replacement parameters after Arjun changes their definitions.
- **Line 103:** Restore safe-update mode to the setting it had before the migration.

## Connections to the other members

- `sensors.spacecraft_id` points to the spacecraft created by **Aryan**.
- `sensors.parameter_id` points to the telemetry definitions created by **Arjun**.
- `readings.sensor_id` points back to `sensors.sensor_id`, forming the path spacecraft → parameter → reading.
- Every new reading activates **Arya's** `create_reading_alert` trigger automatically.
- Alerts are deleted before readings during migration because **Arya's** `alerts.reading_id` is a foreign key.

