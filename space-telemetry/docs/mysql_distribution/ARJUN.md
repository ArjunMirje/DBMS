# Arjun — Telemetry definitions and reading classification

> These are study notes. The source-line numbers refer to the original SQL files. The migration sections are alternatives for upgrading old databases; they are not run after a fresh schema installation.

## Telemetry-parameter table

Source: `database/schema.sql`, lines 25-61

```sql
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

```

### Explanation

- **Lines 25-31:** Create the parameter identity, display name, category, and engineering unit.
- **Lines 32-37:** Store normal and critical boundaries plus the nominal value used for initial readings.
- **Lines 38-41:** Store simulation step size, displayed decimal precision, activity rule, and description.
- **Lines 42-49:** Restrict categories and activity rules to known values.
- **Lines 50-55:** Ensure minimum boundaries are lower than maximum boundaries.
- **Lines 56-59:** Ensure the critical range surrounds the normal range.
- **Lines 60-61:** Limit decimal precision and require a positive simulation step.

## Reading-classification function and insertion procedure

Source: `database/schema.sql`, lines 91-128

```sql
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

```

### Explanation

- **Line 91:** Change the statement delimiter so routines containing semicolons can be created.
- **Lines 92-100:** Define the six inputs needed to classify one reading.
- **Lines 101-105:** Mark the function deterministic and read-only because identical inputs always return the same state.
- **Lines 106-108:** Return `STANDBY` when a conditional sensor is not expected to operate.
- **Lines 109-111:** Return `CRITICAL` when the value leaves the outer safety range.
- **Lines 112-114:** Return `WARNING` when it leaves the normal range but remains inside the critical range.
- **Lines 115-118:** Otherwise return `NORMAL` and close the function.
- **Lines 120-124:** Define a procedure accepting a sensor, measured value, and activity flag.
- **Lines 125-128:** Reject missing values and insert valid readings into Sarish's table.

## Create telemetry definitions during the legacy migration

Source: `database/migrate_v2.sql`, lines 17-61

```sql
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

```

### Explanation

- **Lines 17-40:** Create the normalized telemetry-definition table in the old database, including all range and value constraints.
- **Lines 42-45:** Specify the columns used for the bulk parameter insert.
- **Lines 46-61:** Insert the current fifteen telemetry definitions so the old two-sensor design can be converted to the normalized design.

## Replace four earlier diagnostic definitions

Source: `database/migrate_v3_diagnostics.sql`, lines 20-56

```sql
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

```

### Explanation

- **Line 20:** Temporarily remove the category check because the migration introduces the new Payload category.
- **Lines 22-28:** Convert solar-panel temperature into attitude-pointing error.
- **Lines 29-36:** Convert total power use into the computer-reset counter.
- **Lines 37-43:** Convert computer load into payload operational status.
- **Lines 44-51:** Convert raw radio signal into the easier communication-link-health percentage.
- **Lines 52-56:** Recreate the category constraint, now including `Payload`.

## Connections to the other members

- **Aryan** inserts actual rows into the `telemetry_parameters` structure defined here.
- **Sarish's** `sensors.parameter_id` foreign key points to `telemetry_parameters.parameter_id`.
- **Sarish's** initial-reading query uses `nominal_value` from this table.
- **Arya's** trigger reads these normal and critical limits, then calls `classify_reading` to decide whether an alert is required.
- Aryan's review queries call the same classification function directly for demonstration.

