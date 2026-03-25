-- Solution Monitoring Technical Assignment - SQL Submission
-- Role: Data Analyst | Focus: IoT Health & Connectivity
-- Platform: DuckDB

--------------------------------------------------------------------------------
-- 0. DATA STAGING & CLEANING
-- Goal: Ingest CSVs and normalize data types (dates, timestamps).
--------------------------------------------------------------------------------

-- Clean Device Metadata
CREATE OR REPLACE TABLE iot_devices AS 
SELECT 
    device_id, 
    firmware, 
    network_type, 
    region, 
    -- Parse mixed formats like '2/1/2025 0:00' and ISO '2025-02-01'
    COALESCE(
        try_strptime(installation_date, ['%m/%d/%Y %H:%M', '%m/%d/%Y']),
        try_cast(installation_date AS DATE)
    )::DATE AS installation_date
FROM read_csv_auto('iot_devices.csv', all_varchar=True);

-- Load Measurements
CREATE OR REPLACE TABLE iot_measurements AS 
SELECT * FROM read_csv_auto('iot_measurements.csv');

-- Normalize Error Logs
CREATE OR REPLACE TABLE iot_device_errors AS 
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
-- 1a. Time Coverage: Telemetry (2025-12-23 to 2026-03-23), Errors (2026-01-26 to 2026-03-20).
-- 1b. Scale: 800 devices in metadata/telemetry. 439 in errors.
-- 1c. System Mix: East (232), North (210), West (186), South (172).
-- 1d. Errors: 113 distinct codes. 439 devices with errors, 361 without.
-- 1e. Telemetry Frequency: Nominal interval confirmed at 5 minutes.

-- 1a, 1b, 1e: Coverage, Scale, and Frequency
WITH 
frequency_check AS (
    SELECT gap
    FROM (
        SELECT date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) 
    WHERE gap > 0 
    GROUP BY 1 
    ORDER BY count(*) DESC 
    LIMIT 1
)
SELECT 
    (SELECT count(distinct device_id) FROM iot_devices) as total_devices,
    (SELECT MIN(timestamp) FROM iot_measurements) as telemetry_start,
    (SELECT MAX(timestamp) FROM iot_measurements) as telemetry_end,
    (SELECT MIN(start_time) FROM iot_device_errors) as error_range_start,
    (SELECT MAX(last_seen_at) FROM iot_device_errors) as error_range_end,
    (SELECT gap FROM frequency_check) as nominal_interval_minutes;

-- 1c: System Mix
SELECT region, network_type, count(*) as device_count
FROM iot_devices
GROUP BY region, network_type
ORDER BY region, device_count DESC;

-- 1d: Error Summary
SELECT 
    count(distinct error_code) as distinct_error_codes,
    (SELECT count(distinct device_id) FROM iot_device_errors) as devices_with_errors,
    (SELECT count(distinct m.device_id) 
     FROM iot_measurements m 
     LEFT JOIN iot_device_errors e ON m.device_id = e.device_id 
     WHERE e.device_id IS NULL) as devices_without_errors;

--------------------------------------------------------------------------------
-- QUESTION 2: IDENTIFY CONNECTIVITY PROBLEMS
--------------------------------------------------------------------------------
-- FINDINGS:
-- 2a. Rule 1: 0 devices (No outages >= 2 days). Rule 2: 121 devices.
-- 2b. Top 20: Dominated by IOT_EC1D6B9 (5,770 gap mins) and IOT_3AD643A (5,760 gap mins).
-- 2c. Consistency Check: High correlation between gaps and errors for v2.3.1 Cellular devices.

WITH 
nominal AS (
    SELECT gap FROM (
        SELECT date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) WHERE gap > 0 GROUP BY 1 ORDER BY count(*) DESC LIMIT 1
),
gap_analysis AS (
    SELECT 
        device_id, 
        timestamp as gap_end, 
        date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
),
flagged_devices AS (
    SELECT DISTINCT device_id 
    FROM gap_analysis, nominal
    WHERE gap_minutes >= (2880 + nominal.gap)
    UNION
    SELECT DISTINCT device_id 
    FROM (
        SELECT 
            device_id, 
            count(*) OVER (
                PARTITION BY device_id 
                ORDER BY gap_end 
                RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW
            ) as recurrent_gaps
        FROM gap_analysis, nominal
        WHERE gap_minutes >= (60 + nominal.gap)
    ) 
    WHERE recurrent_gaps >= 3
)
-- 2a: Count of distinct flagged devices
SELECT count(*) as total_problematic_devices FROM flagged_devices;

-- 2b: Top 20 devices by total gap minutes (Last 30 Days)
SELECT 
    device_id, 
    count(*) as gap_events,
    sum(gap_minutes) as total_gap_minutes,
    max(gap_minutes) as max_single_gap_minutes
FROM gap_analysis
WHERE gap_minutes >= 65 
  AND gap_end >= (SELECT MAX(timestamp) - INTERVAL 30 DAYS FROM iot_measurements)
GROUP BY 1
ORDER BY total_gap_minutes DESC
LIMIT 20;

--------------------------------------------------------------------------------
-- QUESTION 3: ISOLATE & PROFILE AFFECTED DEVICES
--------------------------------------------------------------------------------
-- FINDINGS:
-- 3a. Installation Timing: Distributed failure. Dec 2024 (12 devices) and Dec 2021 (42.86% rate).
-- 3b. Error Rate: Flagged (29.89 errors/sys), Healthy (13.29 errors/sys). 2.2x lift.
-- 3c. Extended Silence: 0 devices with > 24h continuous silence.
-- 3d. Trend: Worsening. Gap frequency increased weekly through March 2026.

-- 3a: Installation Cohort Comparison
WITH flagged AS (
    SELECT DISTINCT device_id FROM (
        SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) WHERE gap >= 65
)
SELECT 
    date_trunc('month', installation_date) as install_month,
    count(*) as total_fleet,
    count(f.device_id) as flagged_count,
    round(count(f.device_id) * 100.0 / count(*), 2) as failure_rate_pct
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
GROUP BY 1 ORDER BY 1;

-- 3b: Error Rates (Flagged vs Healthy)
WITH flagged AS (
    SELECT DISTINCT device_id FROM (
        SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) WHERE gap >= 65
)
SELECT 
    CASE WHEN f.device_id IS NOT NULL THEN 'Flagged' ELSE 'Healthy' END as group_label,
    count(distinct d.device_id) as systems,
    round(count(e.device_id) * 1.0 / count(distinct d.device_id), 2) as errors_per_system
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
LEFT JOIN iot_device_errors e ON d.device_id = e.device_id
GROUP BY 1;

-- 3c: Extended Silence (> 24 Hours)
SELECT 
    count(distinct device_id) as devices_with_24h_silence,
    max(gap_minutes) as longest_single_window_minutes
FROM (
    SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM iot_measurements
)
WHERE gap_minutes > 1445; -- 24h + 5m nominal

-- 3d: Weekly Trend for Top 10 Devices
WITH top_10 AS (
    SELECT device_id FROM (
        SELECT device_id, sum(date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp)) as total_gap
        FROM iot_measurements
        GROUP BY 1 ORDER BY 2 DESC LIMIT 10
    )
)
SELECT 
    device_id, 
    date_trunc('week', timestamp) as week,
    sum(date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp)) as weekly_gap_minutes
FROM iot_measurements
WHERE device_id IN (SELECT device_id FROM top_10)
GROUP BY 1, 2
ORDER BY 1, 2;

--------------------------------------------------------------------------------
-- QUESTION 4: SEGMENTATION
--------------------------------------------------------------------------------
-- FINDINGS:
-- 4e. SMOKING GUN: Firmware v2.3.1 + Cellular Network = 92.3% failure rate.
-- All other combinations show 0.0% failure rate for connectivity gaps.

-- 4a, 4b, 4c, 4d: Multidimensional Segmentation
WITH flagged AS (
    SELECT DISTINCT device_id FROM (
        SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) WHERE gap >= 65
)
SELECT 
    d.firmware, 
    d.network_type, 
    count(*) as systems,
    count(f.device_id) as flagged_systems,
    round(count(f.device_id) * 100.0 / count(*), 2) as failure_rate_pct
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
GROUP BY 1, 2
ORDER BY failure_rate_pct DESC;

--------------------------------------------------------------------------------
-- QUESTION 5: ESCALATION LIST
--------------------------------------------------------------------------------
-- FINDINGS:
-- 5b. High Priority (60), Medium (373), Low (367).
-- 5e. Major spike in gap events starting the week of March 9, 2026.

-- 5c: Prioritized Top 20 Escalation List
WITH 
flagged AS (
    SELECT DISTINCT device_id FROM (
        SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) WHERE gap >= 65
),
error_summary AS (
    SELECT device_id, count(*) as error_count FROM iot_device_errors GROUP BY 1
),
priority_ranking AS (
    SELECT 
        d.device_id,
        d.firmware,
        d.network_type,
        COALESCE(e.error_count, 0) as error_count,
        CASE 
            WHEN f.device_id IS NOT NULL AND COALESCE(e.error_count, 0) > 0 THEN 'High'
            WHEN f.device_id IS NOT NULL OR COALESCE(e.error_count, 0) > 5 THEN 'Medium'
            ELSE 'Low'
        END as priority
    FROM iot_devices d
    LEFT JOIN flagged f ON d.device_id = f.device_id
    LEFT JOIN error_summary e ON d.device_id = e.error_count
)
SELECT * 
FROM priority_ranking
ORDER BY 
    CASE priority 
        WHEN 'High' THEN 1 
        WHEN 'Medium' THEN 2 
        WHEN 'Low' THEN 3 
    END ASC,
    error_count DESC
LIMIT 20;

-- 5d: Edge Case Analysis (Gaps but NO errors)
SELECT count(*) as count_gaps_no_errors
FROM iot_devices d
JOIN (SELECT DISTINCT device_id FROM (SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap FROM iot_measurements) WHERE gap >= 65) f ON d.device_id = f.device_id
LEFT JOIN iot_device_errors e ON d.device_id = e.device_id
WHERE e.device_id IS NULL;

-- 5e: Timing Analysis (Weekly Gap Spike)
SELECT 
    date_trunc('week', timestamp) as week,
    count(*) as gap_event_count
FROM (
    SELECT device_id, timestamp, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
    FROM iot_measurements
)
WHERE gap >= 65
GROUP BY 1
ORDER BY 1;
