USE space_telemetry;

SELECT UPPER(name) AS mission_name, YEAR(start_date) AS start_year FROM missions;
SELECT reading_id, ROUND(measured_value, 1) AS rounded_value, DATE(recorded_at) AS reading_date
FROM readings WHERE measured_value > 50 ORDER BY recorded_at DESC;

SELECT c.name, r.measured_value
FROM spacecraft c JOIN sensors s ON c.spacecraft_id = s.spacecraft_id
JOIN readings r ON s.sensor_id = r.sensor_id
WHERE s.sensor_type = 'Battery';

SELECT sensor_id, COUNT(*) AS total, AVG(measured_value) AS average
FROM readings GROUP BY sensor_id HAVING COUNT(*) >= 2;

SELECT sensor_id, sensor_type FROM sensors
WHERE sensor_id IN (
    SELECT r.sensor_id FROM readings r JOIN alerts a ON a.reading_id = r.reading_id
);

SELECT c.name FROM spacecraft c JOIN sensors s ON c.spacecraft_id = s.spacecraft_id
WHERE s.sensor_type = 'Temperature'
UNION
SELECT c.name FROM spacecraft c JOIN sensors s ON c.spacecraft_id = s.spacecraft_id
WHERE s.sensor_type = 'Battery';

SELECT classify_reading(20, 20, 100) AS boundary_state;

SELECT COUNT(*) AS before_readings FROM readings;
SELECT COUNT(*) AS before_alerts FROM alerts;
START TRANSACTION;
CALL add_reading(1, 75);
SELECT COUNT(*) AS during_readings FROM readings;
SELECT COUNT(*) AS during_alerts FROM alerts;
ROLLBACK;
SELECT COUNT(*) AS after_readings FROM readings;
SELECT COUNT(*) AS after_alerts FROM alerts;

START TRANSACTION;
INSERT INTO missions (name, purpose, start_date)
VALUES ('Temporary DELETE demo', 'Review only', CURRENT_DATE());
DELETE FROM missions WHERE mission_id = LAST_INSERT_ID();
ROLLBACK;

SHOW INDEX FROM readings;
EXPLAIN SELECT * FROM readings
WHERE sensor_id = 1 AND recorded_at >= '2026-10-01 00:00:00';