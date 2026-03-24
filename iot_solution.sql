-- Solution Monitoring Technical Assignment
-- DuckDB SQL Solution
-- Role: Senior Data Analyst specializing in IoT Telemetry and SQL

-- ==========================================
-- 0. DATA INGESTION & CLEANING
-- ==========================================

CREATE OR REPLACE TABLE devices AS 
SELECT 
    device_id, 
    firmware, 
    network_type, 
    region, 
    -- Clean installation_date to standard DATE format
    CASE 
        WHEN installation_date LIKE '%-%' THEN TRY_CAST(SUBSTR(installation_date, 1, 10) AS DATE)
        WHEN installation_date LIKE '%/%' THEN 
            CASE 
                WHEN strpos(installation_date, ' ') > 0 THEN TRY_CAST(strptime(SUBSTR(installation_date, 1, strpos(installation_date, ' ') - 1), '%m/%d/%Y') AS DATE)
                ELSE TRY_CAST(strptime(installation_date, '%m/%d/%Y') AS DATE)
            END
        ELSE TRY_CAST(installation_date AS DATE)
    END as install_date
FROM read_csv_auto('iot_devices.csv');

CREATE OR REPLACE TABLE measurements AS 
SELECT device_id, timestamp, voltage_v, current_a
FROM read_csv_auto('iot_measurements.csv');

CREATE OR REPLACE TABLE errors AS 
SELECT 
    device_id, 
    error_code, 
    TRY_CAST(start_time AS TIMESTAMP) as start_time, 
    TRY_CAST(last_seen_at AS TIMESTAMP) as last_seen_at
FROM read_csv_auto('iot_device_errors.csv');

-- ==========================================
-- QUESTION 1: UNDERSTAND THE DATA
-- ==========================================

-- 1.a Time Coverage
CREATE OR REPLACE TABLE q1_a_coverage AS
SELECT 'Telemetry' as source, MIN(timestamp) as start_ts, MAX(timestamp) as end_ts FROM measurements
UNION ALL
SELECT 'Errors' as source, MIN(start_time) as start_ts, MAX(last_seen_at) as end_ts FROM errors;

-- 1.b Scale
CREATE OR REPLACE TABLE q1_b_scale AS
SELECT 
    (SELECT count(distinct device_id) FROM devices) as devices_metadata,
    (SELECT count(distinct device_id) FROM measurements) as devices_telemetry,
    (SELECT count(distinct device_id) FROM errors) as devices_errors;

-- 1.d Errors
-- Part 3: Distinct devices with at least one error row
-- Part 4: Devices in telemetry with NO error rows
CREATE OR REPLACE TABLE q1_d_errors AS
SELECT 
    'Devices with Errors' as metric, count(distinct device_id) as value FROM errors
UNION ALL
SELECT 
    'Devices without Errors' as metric, count(distinct m.device_id) as value 
FROM (SELECT DISTINCT device_id FROM measurements) m 
LEFT JOIN (SELECT DISTINCT device_id FROM errors) e ON m.device_id = e.device_id 
WHERE e.device_id IS NULL;

-- 1.e Telemetry Cadence
-- Infer nominal interval (median gap)
CREATE OR REPLACE TABLE q1_e_cadence AS
WITH gaps AS (
    SELECT date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap
    FROM measurements
)
SELECT gap as nominal_interval_minutes, count(*) as frequency
FROM gaps WHERE gap > 0
GROUP BY 1 ORDER BY 2 DESC LIMIT 1;

-- ==========================================
-- QUESTION 2: IDENTIFY CONNECTIVITY PROBLEMS
-- ==========================================

-- Define Gaps
CREATE OR REPLACE TABLE gaps_base AS
SELECT 
    device_id, 
    timestamp as current_ts, 
    LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_ts,
    date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
FROM measurements;

-- Identify Problematic Devices (Rules 1 & 2)
CREATE OR REPLACE TABLE problematic_devices AS
-- Rule 1: Long Gap (>= 2 days / 2880 mins + nominal 5 mins)
SELECT DISTINCT device_id, 'Rule 1: Long Gap' as reason FROM gaps_base WHERE gap_minutes >= 2885
UNION
-- Rule 2: Short Recurring Gaps (>= 3 gaps of >= 1hr in 7 days)
SELECT DISTINCT device_id, 'Rule 2: Short Recurring' as reason FROM (
    SELECT device_id, current_ts, count(*) OVER (PARTITION BY device_id ORDER BY current_ts RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW) as gap_count_7d
    FROM gaps_base WHERE gap_minutes >= 65
) WHERE gap_count_7d >= 3;

-- 2.b Top 20 Devices by Total Gap Minutes (Last 30 Days)
CREATE OR REPLACE TABLE top_20_gaps AS
SELECT 
    device_id, 
    count(*) as gap_events,
    sum(gap_minutes) as total_gap_minutes,
    max(gap_minutes) as max_single_gap_minutes
FROM gaps_base
WHERE gap_minutes >= 65 
  AND current_ts >= (SELECT MAX(timestamp) - INTERVAL 30 DAYS FROM measurements)
GROUP BY 1
ORDER BY total_gap_minutes DESC
LIMIT 20;

-- 2.c Consistency Check: Error activity for Top 20
CREATE OR REPLACE TABLE top_20_error_check AS
SELECT t20.*, count(e.error_code) as error_count
FROM top_20_gaps t20
LEFT JOIN errors e ON t20.device_id = e.device_id 
  AND e.start_time >= (SELECT MAX(timestamp) - INTERVAL 30 DAYS FROM measurements)
GROUP BY t20.device_id, t20.gap_events, t20.total_gap_minutes, t20.max_single_gap_minutes
ORDER BY total_gap_minutes DESC;

-- ==========================================
-- QUESTION 3: ISOLATE & PROFILE
-- ==========================================

-- 3.a Installation Timing (Flagged vs Full Fleet)
-- "Flagged" = is_problematic (from Question 2)
CREATE OR REPLACE TABLE q3_a_install_cohorts AS
SELECT 
    date_trunc('month', install_date) as install_month,
    count(*) as total_fleet,
    count(CASE WHEN device_id IN (SELECT device_id FROM problematic_devices) THEN 1 END) as flagged_count,
    round(count(CASE WHEN device_id IN (SELECT device_id FROM problematic_devices) THEN 1 END) * 100.0 / count(*), 2) as failure_rate
FROM devices
GROUP BY 1 ORDER BY 1;

-- 3.b Error Comparison (Flagged vs Non-Flagged)
-- "Non-Flagged" = Healthy
CREATE OR REPLACE TABLE q3_b_error_comparison AS
SELECT 
    CASE WHEN p.device_id IS NOT NULL THEN 'Flagged (Gaps)' ELSE 'Healthy (No Gaps)' END as status,
    count(distinct d.device_id) as device_count,
    count(e.error_code) as total_errors,
    round(count(e.error_code) * 1.0 / count(distinct d.device_id), 2) as errors_per_system
FROM devices d
LEFT JOIN problematic_devices p ON d.device_id = p.device_id
LEFT JOIN errors e ON d.device_id = e.device_id
GROUP BY 1;

-- 3.c Extended Silence (> 24 Hours)
CREATE OR REPLACE TABLE q3_c_silence AS
SELECT 
    count(distinct device_id) as devices_with_24h_silence,
    max(gap_minutes) as longest_single_window_minutes
FROM gaps_base
WHERE gap_minutes > 1445; -- 24h + 5m nominal

-- 3.d Weekly Trend for Top 10 Devices
CREATE OR REPLACE TABLE top_10_weekly_trend AS
WITH top_10 AS (
    SELECT device_id FROM top_20_gaps LIMIT 10
)
SELECT 
    device_id, 
    date_trunc('week', current_ts) as week,
    sum(gap_minutes) as weekly_gap_minutes
FROM gaps_base
WHERE device_id IN (SELECT device_id FROM top_10)
  AND gap_minutes >= 65
GROUP BY 1, 2
ORDER BY 1, 2;

-- ==========================================
-- QUESTION 4: SEGMENTATION
-- ==========================================

-- 4.c Segmentation by Region
CREATE OR REPLACE TABLE q4_c_region AS
SELECT 
    region, 
    count(*) as total_devices,
    count(p.device_id) as flagged_devices,
    round(count(p.device_id) * 100.0 / count(*), 2) as failure_rate
FROM devices d
LEFT JOIN problematic_devices p ON d.device_id = p.device_id
GROUP BY 1 ORDER BY 4 DESC;

-- 4.e Final Check for 0% failure in other segments
CREATE OR REPLACE TABLE q4_e_segment_check AS
SELECT d.firmware, d.network_type, 
       count(*) as total_devices,
       count(p.device_id) as problematic_count,
       round(count(p.device_id) * 100.0 / count(*), 2) as failure_rate
FROM devices d
LEFT JOIN problematic_devices p ON d.device_id = p.device_id
GROUP BY 1, 2 ORDER BY 5 DESC;

-- ==========================================
-- QUESTION 5: ESCALATION LIST
-- ==========================================

-- 5.a/b Priority Rules Application
CREATE OR REPLACE TABLE fleet_priority AS
SELECT 
    d.device_id,
    d.firmware,
    d.network_type,
    d.region,
    CASE WHEN p.device_id IS NOT NULL THEN 1 ELSE 0 END as is_flagged,
    COALESCE(e.err_count, 0) as error_count,
    CASE 
        WHEN p.device_id IS NOT NULL AND COALESCE(e.err_count, 0) > 0 THEN 'High'
        WHEN p.device_id IS NOT NULL OR COALESCE(e.err_count, 0) > 5 THEN 'Medium'
        ELSE 'Low'
    END as priority
FROM devices d
LEFT JOIN problematic_devices p ON d.device_id = p.device_id
LEFT JOIN (SELECT device_id, count(*) as err_count FROM errors GROUP BY 1) e ON d.device_id = e.device_id;

-- 5.c Top 20 Escalation List
CREATE OR REPLACE TABLE top_20_escalation AS
SELECT 
    f.device_id,
    f.priority,
    f.firmware,
    f.network_type,
    f.error_count,
    COALESCE(g.total_gap_minutes, 0) as gap_minutes_last_30d,
    'Connectivity gaps + active error logs' as reason
FROM fleet_priority f
LEFT JOIN top_20_gaps g ON f.device_id = g.device_id
WHERE f.priority = 'High'
ORDER BY gap_minutes_last_30d DESC
LIMIT 20;

-- 5.d Edge Case: Long absence but NO errors
CREATE OR REPLACE TABLE q5_d_edge_case AS
SELECT 
    count(distinct d.device_id) as count
FROM devices d
JOIN problematic_devices p ON d.device_id = p.device_id
LEFT JOIN errors e ON d.device_id = e.device_id
WHERE e.device_id IS NULL;
