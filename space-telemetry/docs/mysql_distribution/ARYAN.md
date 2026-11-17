# Aryan — Database setup, sample data, and review queries

> These are study notes. The source-line numbers refer to the original SQL files. The migration sections are alternatives for upgrading old databases; they are not run after a fresh schema installation.

## Database and spacecraft structure

Source: `database/schema.sql`, lines 1-24

```sql
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

```

### Explanation

- **Lines 1-2:** Create the `space_telemetry` database with full Unicode support, then select it for subsequent commands.
- **Lines 4-9:** Create `missions`. The auto-increment key uniquely identifies each mission; the name is required and cannot repeat.
- **Lines 11-18:** Create `spacecraft` and connect each spacecraft to one mission through `mission_id`.
- **Lines 19-23:** Add checks so status, sunlight/eclipse state, and ground-contact state can contain only permitted values.

## Mission, spacecraft, and telemetry sample data

Source: `database/schema.sql`, lines 165-205

```sql
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

```

### Explanation

- **Lines 165-166:** Insert the demonstration Earth-observation mission.
- **Lines 168-169:** Insert `Satellite-01` and connect it to mission 1.
- **Lines 171-174:** Name all columns that every telemetry definition must supply.
- **Lines 176-181:** Insert the three thermal measurements and attitude-pointing error, including their normal, warning, and critical boundaries.
- **Lines 182-189:** Insert the main power measurements: battery charge, battery voltage, regulated bus voltage, and solar-array current.
- **Lines 190-195:** Insert battery current, reset count, and reaction-wheel speed.
- **Lines 196-201:** Insert angular rate, onboard-storage usage, and the numeric payload-status code.
- **Lines 202-205:** Insert communication-link health, which is expected only during ground contact.

## Initial setup part of the legacy migration

Source: `database/migrate_v2.sql`, lines 1-16

```sql
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

```

### Explanation

- **Lines 1-2:** State the migration's purpose and select the existing database.
- **Lines 3-4:** Remember Workbench's safe-update setting and temporarily turn it off so controlled migration updates can run.
- **Lines 6-8:** Remove the old trigger, procedure, and function before their upgraded definitions are installed by Arya's section.
- **Lines 10-16:** Add orbit, contact, and simulation state to the old `spacecraft` table and restrict the allowed text values.

## DBMS review queries

Source: `database/review_queries.sql`, lines 1-44

```sql
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
```

### Explanation

- **Lines 1-4:** Select the database, uppercase the mission name, and extract the year from its start date.
- **Lines 6-12:** Join readings to sensors and telemetry definitions so a numeric reading is displayed with its name and unit.
- **Lines 14-19:** Group readings by parameter and calculate count and average; `HAVING` filters the grouped results.
- **Lines 21-29:** Use a nested query to find only parameters that have generated an alert.
- **Lines 31-33:** Use `UNION` to combine power and thermal parameter names without duplicates.
- **Lines 35-39:** Call Arjun's classification function with normal, warning, critical, and standby examples.
- **Lines 41-44:** Display the reading indexes and use `EXPLAIN` to show how MySQL plans a sensor-and-time query.

## Connections to the other members

- `spacecraft.mission_id` connects this code to `missions.mission_id` in the same section.
- The telemetry rows inserted here must match the columns and constraints created in **Arjun's** `telemetry_parameters` table.
- **Sarish's** sensor rows connect `Satellite-01` to these telemetry parameters.
- The review joins travel from **Sarish's** `readings` to `sensors`, then to **Arjun's** `telemetry_parameters`.
- The review calls `classify_reading`, which is defined in **Arjun's** code.
- The migration drops old automation here so **Arya's** migration code can recreate the updated versions safely.

