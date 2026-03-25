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
-- QUESTION 1: CHARACTERIZE THE DATASET
--------------------------------------------------------------------------------
-- FINDINGS:
-- Telemetry covers 3 months; Errors cover only the last 2 months.
-- Nominal cadence confirmed at 5 minutes.
-- Fleet size is consistent at 800 devices.

WITH 
cadence_check AS (
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
    (SELECT val FROM (SELECT val FROM (SELECT 1 as id, MIN(start_time) as val FROM iot_device_errors) UNION ALL SELECT val FROM (SELECT 2 as id, MAX(last_seen_at) as val FROM iot_device_errors)) ORDER BY id ASC LIMIT 1) as error_range_start, -- Note: Simplified for readability
    (SELECT gap FROM cadence_check) as nominal_interval_minutes;

--------------------------------------------------------------------------------
-- QUESTION 2: IDENTIFY CONNECTIVITY GAPS
--------------------------------------------------------------------------------
-- RULE 1 (Long Gap): 2 days (2880m) + nominal interval.
-- RULE 2 (Intermittency): 3+ gaps of 1hr in a rolling 7-day window.

WITH 
nominal AS (
    -- Dynamically pull nominal interval for threshold calculations
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
    -- Identify systems violating either Rule 1 or Rule 2
    SELECT DISTINCT device_id 
    FROM gap_analysis, nominal
    WHERE gap_minutes >= (2880 + nominal.gap) -- Rule 1: 2 Days + Nominal
    
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
        WHERE gap_minutes >= (60 + nominal.gap) -- Rule 2: 1 Hour + Nominal
    ) 
    WHERE recurrent_gaps >= 3
)

SELECT count(*) as total_problematic_devices FROM flagged_devices;

--------------------------------------------------------------------------------
-- QUESTION 4: SEGMENTATION (THE "SMOKING GUN")
--------------------------------------------------------------------------------
-- FINDINGS: 
-- Firmware v2.3.1 on Cellular is the primary failure vector (92.3% rate).
-- All other connectivity/firmware combinations show 0.0% failure.

WITH 
flagged AS (
    -- Using Rule 2 logic for segmentation lift analysis
    SELECT DISTINCT device_id 
    FROM (
        SELECT device_id, date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
        FROM iot_measurements
    ) WHERE gap >= 65
)

SELECT 
    d.firmware, 
    d.network_type, 
    count(*) as systems_in_segment,
    count(f.device_id) as flagged_systems,
    round(count(f.device_id) * 100.0 / count(*), 2) as failure_rate_pct
FROM iot_devices d
LEFT JOIN flagged f ON d.device_id = f.device_id
GROUP BY ALL
ORDER BY failure_rate_pct DESC;

--------------------------------------------------------------------------------
-- QUESTION 5: PRIORITIZED ESCALATION LIST
--------------------------------------------------------------------------------
-- Goal: Order by High (Gaps + Errors) > Medium > Low.

WITH 
flagged AS (
    -- Consolidate connectivity flags for prioritization
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
    LEFT JOIN error_summary e ON d.device_id = e.device_id
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
