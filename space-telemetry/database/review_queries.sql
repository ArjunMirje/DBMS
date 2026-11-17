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
