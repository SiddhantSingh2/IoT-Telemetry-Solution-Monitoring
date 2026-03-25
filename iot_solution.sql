-- Solution Monitoring Technical Assignment - SQL Submission
-- Candidate: Data Analyst
-- Platform: DuckDB
-- Focus: IoT Device Health & Connectivity Monitoring

--------------------------------------------------------------------------------
-- 0. DATA PREPARATION
-- Load CSV files as tables and handle data cleaning, particularly date formats.
--------------------------------------------------------------------------------

-- Create base tables to be referenced in the analysis CTEs
CREATE OR REPLACE TABLE iot_devices_base AS 
SELECT 
    device_id, 
    firmware, 
    network_type, 
    region, 
    -- Handling mixed formats: '2/1/2025 0:00', '4/30/2021', nulls, and 'NaT'
    COALESCE(
        try_strptime(installation_date, ['%m/%d/%Y %H:%M', '%m/%d/%Y']),
        try_cast(installation_date AS DATE)
    )::DATE AS installation_date
FROM read_csv_auto('iot_devices.csv', all_varchar=True);

CREATE OR REPLACE TABLE iot_measurements_base AS 
SELECT * FROM read_csv_auto('iot_measurements.csv');

CREATE OR REPLACE TABLE iot_device_errors_base AS 
SELECT 
    device_id, 
    error_code, 
    try_cast(start_time AS TIMESTAMP) as start_time, 
    try_cast(last_seen_at AS TIMESTAMP) as last_seen_at
FROM read_csv_auto('iot_device_errors.csv');

--------------------------------------------------------------------------------
-- QUESTION 1: UNDERSTAND THE DATA
--------------------------------------------------------------------------------
WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),
     iot_device_errors AS (SELECT * FROM iot_device_errors_base)

-- Profiling Time Coverage, Scale, and Cadence
SELECT 'Telemetry Range' as metric, MIN(timestamp)::VARCHAR || ' to ' || MAX(timestamp)::VARCHAR as value FROM iot_measurements
UNION ALL
SELECT 'Error Range' as metric, MIN(start_time)::VARCHAR || ' to ' || MAX(last_seen_at)::VARCHAR as value FROM iot_device_errors
UNION ALL
SELECT 'Fleet Size' as metric, count(distinct device_id)::VARCHAR FROM iot_devices
UNION ALL
SELECT 'Nominal Interval' as metric, 
    (WITH gaps AS (SELECT date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as g FROM iot_measurements)
     SELECT g FROM gaps WHERE g > 0 GROUP BY 1 ORDER BY count(*) DESC LIMIT 1)::VARCHAR;

--------------------------------------------------------------------------------
-- QUESTION 2: IDENTIFY CONNECTIVITY PROBLEMS
--------------------------------------------------------------------------------
WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),
     iot_device_errors AS (SELECT * FROM iot_device_errors_base),

gaps_base AS (
    SELECT 
        device_id, 
        timestamp as current_ts, 
        date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
),

problematic_devices AS (
    -- Rule 1: Long Gap (>= 2 days)
    SELECT DISTINCT device_id FROM gaps_base WHERE gap_minutes >= 2885
    UNION
    -- Rule 2: Short Recurring (>= 3 gaps of >= 1hr in 7 days)
    SELECT DISTINCT device_id FROM (
        SELECT device_id, count(*) OVER (PARTITION BY device_id ORDER BY current_ts RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW) as cnt
        FROM gaps_base WHERE gap_minutes >= 65
    ) WHERE cnt >= 3
)

-- Resulting Flagged Fleet
SELECT count(*) as flagged_device_count FROM problematic_devices;

-- Note: Intermediate tables for README generation were created using this logic in the previous session.
-- The final submission SQL focuses on the core analytical flow.

--------------------------------------------------------------------------------
-- QUESTION 4: SEGMENTATION - ISOLATING THE SMOKING GUN
--------------------------------------------------------------------------------
WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),
     
gaps_base AS (
    SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
),
flagged AS (
    SELECT DISTINCT device_id FROM gaps_base WHERE gap_minutes >= 65 -- Simplified flag for segmentation view
)

-- Lift Analysis by Segment
SELECT 
    d.firmware, 
    d.network_type, 
    count(*) as total_systems,
    count(f.device_id) as problematic_systems,
    round(count(f.device_id) * 100.0 / count(*), 2) as failure_rate
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
GROUP BY 1, 2
ORDER BY 5 DESC;

--------------------------------------------------------------------------------
-- QUESTION 5: ESCALATION PRIORITIZATION
--------------------------------------------------------------------------------
WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_device_errors AS (SELECT * FROM iot_device_errors_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),

gaps_base AS (
    SELECT device_id, timestamp, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
),
flagged AS (
    SELECT DISTINCT device_id FROM (
        SELECT device_id, count(*) OVER (PARTITION BY device_id ORDER BY timestamp RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW) as cnt
        FROM gaps_base WHERE gap_minutes >= 65
    ) WHERE cnt >= 3
),
err_counts AS (
    SELECT device_id, count(*) as total_errors FROM iot_device_errors GROUP BY 1
)

SELECT 
    d.device_id,
    CASE 
        WHEN f.device_id IS NOT NULL AND COALESCE(e.total_errors, 0) > 0 THEN 'High'
        WHEN f.device_id IS NOT NULL OR COALESCE(e.total_errors, 0) > 5 THEN 'Medium'
        ELSE 'Low'
    END as priority,
    d.firmware,
    d.network_type,
    COALESCE(e.total_errors, 0) as error_count
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
LEFT JOIN err_counts e ON d.device_id = e.device_id
ORDER BY 2 ASC, 5 DESC
LIMIT 20;
