-- Solution Monitoring Technical Assignment
-- DuckDB SQL Solution
-- Role: Senior Data Analyst specializing in IoT Telemetry and SQL

-- Creating Temporary Tables for Persistence across statements
CREATE OR REPLACE TABLE devices AS 
SELECT device_id, firmware, network_type, region, 
       COALESCE(TRY_CAST(SUBSTR(installation_date, 1, 10) AS DATE), TRY_CAST(installation_date AS DATE)) as install_date
FROM read_csv_auto('iot_devices.csv');

CREATE OR REPLACE TABLE measurements AS 
SELECT device_id, timestamp, voltage_v, current_a
FROM read_csv_auto('iot_measurements.csv');

CREATE OR REPLACE TABLE errors AS 
SELECT device_id, error_code, TRY_CAST(start_time AS TIMESTAMP) as start_time, TRY_CAST(last_seen_at AS TIMESTAMP) as last_seen_at
FROM read_csv_auto('iot_device_errors.csv');

-- Question 1: Data Profiling
CREATE OR REPLACE TABLE q1_profiling AS
SELECT 'Telemetry' as source, MIN(timestamp) as start_ts, MAX(timestamp) as end_ts, count(distinct device_id) as sys_count FROM measurements
UNION ALL
SELECT 'Errors' as source, MIN(start_time) as start_ts, MAX(last_seen_at) as end_ts, count(distinct device_id) as sys_count FROM errors;

-- Question 2: Gap Analysis
CREATE OR REPLACE TABLE gaps_base AS
SELECT device_id, timestamp as current_ts, LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_ts,
       date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
FROM measurements;

CREATE OR REPLACE TABLE problematic_devices AS
SELECT DISTINCT device_id FROM gaps_base WHERE gap_minutes >= 2885
UNION
SELECT DISTINCT device_id FROM (
    SELECT device_id, current_ts, count(*) OVER (PARTITION BY device_id ORDER BY current_ts RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW) as gap_count_7d
    FROM gaps_base WHERE gap_minutes >= 65
) WHERE gap_count_7d >= 3;

-- Question 3 & 4: Segmentation & Lift
CREATE OR REPLACE TABLE segmentation AS
SELECT d.*, CASE WHEN p.device_id IS NOT NULL THEN 1 ELSE 0 END as is_problematic, COALESCE(e.error_count, 0) as error_count
FROM devices d
LEFT JOIN (SELECT device_id, count(*) as error_count FROM errors GROUP BY 1) e ON d.device_id = e.device_id
LEFT JOIN problematic_devices p ON d.device_id = p.device_id;

-- Question 5: Escalation
CREATE OR REPLACE VIEW escalation_list AS 
SELECT *, CASE 
    WHEN is_problematic = 1 AND error_count > 0 THEN 'High' 
    WHEN is_problematic = 1 OR error_count > 5 THEN 'Medium' 
    ELSE 'Low' 
END as priority
FROM segmentation;
