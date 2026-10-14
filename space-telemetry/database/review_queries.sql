-- Run sections individually in MySQL Workbench after schema.sql.
USE space_telemetry;

-- Unit 3: SELECT, filtering, string/date/numeric functions, ordering.
SELECT UPPER(name) AS mission_name, YEAR(start_date) AS start_year FROM missions;
SELECT reading_id, ROUND(measured_value, 1) AS rounded_value, DATE(recorded_at) AS reading_date
FROM readings WHERE measured_value > 50 ORDER BY recorded_at DESC;

-- Unit 3: JOIN and selection/projection mapping from relational algebra.
-- Select Battery sensors, join their readings, project spacecraft name/value.
SELECT c.name, r.measured_value
FROM spacecraft c JOIN sensors s ON c.spacecraft_id = s.spacecraft_id
JOIN readings r ON s.sensor_id = r.sensor_id
WHERE s.sensor_type = 'Battery';

-- Unit 3: aggregate, GROUP BY, HAVING.
SELECT sensor_id, COUNT(*) AS total, AVG(measured_value) AS average
FROM readings GROUP BY sensor_id HAVING COUNT(*) >= 2;

-- Unit 3: nested query. Sensors whose readings caused alerts.
SELECT sensor_id, sensor_type FROM sensors
WHERE sensor_id IN (
    SELECT r.sensor_id FROM readings r JOIN alerts a ON a.reading_id = r.reading_id
);

-- Unit 3: UNION combines spacecraft names having either sensor type.
SELECT c.name FROM spacecraft c JOIN sensors s ON c.spacecraft_id = s.spacecraft_id
WHERE s.sensor_type = 'Temperature'
UNION
SELECT c.name FROM spacecraft c JOIN sensors s ON c.spacecraft_id = s.spacecraft_id
WHERE s.sensor_type = 'Battery';

-- Unit 3: function call. Exact boundaries are NORMAL.
SELECT classify_reading(20, 20, 100) AS boundary_state;

-- Unit 3/4: TCL. Both reading and trigger alert disappear on rollback.
SELECT COUNT(*) AS before_readings FROM readings;
SELECT COUNT(*) AS before_alerts FROM alerts;
START TRANSACTION;
CALL add_reading(1, 75);
SELECT COUNT(*) AS during_readings FROM readings;
SELECT COUNT(*) AS during_alerts FROM alerts;
ROLLBACK;
SELECT COUNT(*) AS after_readings FROM readings;
SELECT COUNT(*) AS after_alerts FROM alerts;

-- Unit 3: DELETE demonstration on a temporary row, rolled back.
-- The temporary mission has no child spacecraft, so no foreign key is broken.
START TRANSACTION;
INSERT INTO missions (name, purpose, start_date)
VALUES ('Temporary DELETE demo', 'Review only', CURRENT_DATE());
DELETE FROM missions WHERE mission_id = LAST_INSERT_ID();
ROLLBACK;

-- Unit 4: index and query-plan inspection.
SHOW INDEX FROM readings;
EXPLAIN SELECT * FROM readings
WHERE sensor_id = 1 AND recorded_at >= '2026-10-01 00:00:00';
-- Small demo tables may use a full scan; this is not evidence of an index failure.
-- InnoDB chooses a plan based on its cost estimate.

-- Optional DCL, run separately as a MySQL administrator after changing the password.
-- CREATE USER 'space_app'@'127.0.0.1' IDENTIFIED BY 'REPLACE_WITH_YOUR_OWN_PASSWORD';
-- GRANT SELECT, INSERT, UPDATE ON space_telemetry.* TO 'space_app'@'127.0.0.1';
-- GRANT EXECUTE ON space_telemetry.* TO 'space_app'@'127.0.0.1';
-- REVOKE UPDATE ON space_telemetry.* FROM 'space_app'@'127.0.0.1';
-- The final REVOKE demonstrates DCL; grant UPDATE again to restore status/acknowledge actions.
