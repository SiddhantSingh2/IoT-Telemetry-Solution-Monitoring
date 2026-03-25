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
-- FINDINGS:
-- 1a. Time Coverage: 
--     Telemetry: 2025-12-23 to 2026-03-23
--     Errors: 2026-01-26 to 2026-03-20
--     Implication: Error logs are truncated and only cover the latter 2/3 of the telemetry period.
-- 1b. Scale: 800 devices total. All 800 appear in both metadata and telemetry. 
--     439 devices have at least one error log.
-- 1c. System Mix: East (232), North (210), West (186), South (172). 
--     Cellular (130), Broadband (344), Fiber (326).
-- 1d. Errors: 113 distinct codes. 361 devices have NO error logs. 
--     Top code: 'MissingData.Status' (found in connectivity-flagged systems).
-- 1e. Cadence: Nominal interval is 5 minutes.

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
SELECT 'Devices with Errors' as metric, (SELECT count(distinct device_id) FROM iot_device_errors)::VARCHAR
UNION ALL
SELECT 'Nominal Interval' as metric, 
    (WITH gaps AS (SELECT date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as g FROM iot_measurements)
     SELECT g FROM gaps WHERE g > 0 GROUP BY 1 ORDER BY count(*) DESC LIMIT 1)::VARCHAR;

--------------------------------------------------------------------------------
-- QUESTION 2: IDENTIFY CONNECTIVITY PROBLEMS
--------------------------------------------------------------------------------
-- FINDINGS:
-- 2a. Rule 1 (Long Gap >= 2 days): 0 devices. No single long outage.
--     Rule 2 (Short Recurring >= 3 gaps of 1hr in 7 days): 121 devices.
-- 2b. Top 20: Dominated by Cellular systems losing ~10-15% of uptime (e.g., IOT_EC1D6B9 with 5,770 gap mins).
-- 2c. Consistency Check: High correlation between gaps and errors for most systems. 
--     However, 61 flagged systems have ZERO error logs, indicating "silent" crashes.

WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),

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

--------------------------------------------------------------------------------
-- QUESTION 3: ISOLATE & PROFILE
--------------------------------------------------------------------------------
-- FINDINGS:
-- 3a. Installation Timing: Failures are widespread. Dec 2024 has the highest volume (12). 
--     Dec 2021 has a high rate (42.86%). No evidence of "old age" hardware hardware failure.
-- 3b. Error Rate: Flagged systems have 29.89 errors/sys (3.74/wk). 
--     Healthy systems have 13.29 errors/sys (1.66/wk). Lift is 2.2x.
-- 3c. Extended Silence (> 24h): 0 devices. Modems eventually recover.
-- 3d. Trend: Worsening. Gap minutes increased weekly through March 2026.

WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),
     iot_device_errors AS (SELECT * FROM iot_device_errors_base),

gaps_base AS (
    SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
),
flagged AS (
    SELECT DISTINCT device_id FROM gaps_base WHERE gap_minutes >= 65
)

SELECT 
    CASE WHEN f.device_id IS NOT NULL THEN 'Flagged (Gaps)' ELSE 'Healthy (No Gaps)' END as status,
    count(distinct d.device_id) as device_count,
    count(e.error_code) as total_errors,
    round(count(e.error_code) * 1.0 / count(distinct d.device_id), 2) as errors_per_system
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
LEFT JOIN iot_device_errors e ON d.device_id = e.device_id
GROUP BY 1;

--------------------------------------------------------------------------------
-- QUESTION 4: SEGMENTATION - ISOLATING THE SMOKING GUN
--------------------------------------------------------------------------------
-- FINDINGS:
-- 4a. Firmware: Only v2.3.1 is failing. All other firmwares have 0% gap rate.
-- 4b. Network: Only Cellular is failing. Fiber and Broadband have 0% gap rate.
-- 4c. Region: East is highest (34%), but this is driven by high v2.3.1 Cellular density there.
-- 4e. SMOKING GUN: Firmware v2.3.1 + Cellular Network = 92.3% failure rate. 
--     All other 8 segments in the fleet have a 0.0% failure rate for connectivity gaps.

WITH iot_devices AS (SELECT * FROM iot_devices_base),
     iot_measurements AS (SELECT * FROM iot_measurements_base),
     
gaps_base AS (
    SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
),
flagged AS (
    SELECT DISTINCT device_id FROM gaps_base WHERE gap_minutes >= 65
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
-- FINDINGS:
-- 5a. Rules: High = Gaps + Errors. Medium = Gaps only OR high errors (>5).
-- 5b. Distribution: High (60), Medium (373), Low (367).
-- 5d. Edge Case: 61 devices have gaps but NO error logs (likely total system crashes).
-- 5e. Timing: Issues spiked dramatically starting the week of March 9, 2026.

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

-- Top 20 Escalation List
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
