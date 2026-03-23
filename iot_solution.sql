-- Solution Monitoring Technical Assignment
-- DuckDB SQL Solution

-- Data Loading CTEs
WITH devices AS (
    SELECT 
        device_id,
        firmware,
        network_type,
        region,
        CAST(strptime(installation_date, '%m/%d/%Y') AS DATE) as installation_date
    FROM read_csv_auto('iot_devices.csv')
),
measurements AS (
    SELECT 
        device_id,
        timestamp,
        voltage_v,
        current_a
    FROM read_csv_auto('iot_measurements.csv')
),
errors AS (
    SELECT 
        device_id,
        error_code,
        CAST(strptime(left(start_time, 19), '%Y-%m-%dT%H:%M:%S') AS TIMESTAMP) as start_time,
        CAST(strptime(left(last_seen_at, 19), '%Y-%m-%dT%H:%M:%S') AS TIMESTAMP) as last_seen_at
    FROM read_csv_auto('iot_device_errors.csv')
),

-- Question 1: Data Profiling
q1a_time_ranges AS (
    SELECT 
        'measurements' as source,
        MIN(timestamp) as min_ts,
        MAX(timestamp) as max_ts,
        count(*) as total_records
    FROM measurements
    UNION ALL
    SELECT 
        'errors' as source,
        MIN(start_time) as min_ts,
        MAX(last_seen_at) as max_ts,
        count(*) as total_records
    FROM errors
),

q1b_device_counts AS (
    SELECT 
        (SELECT count(distinct device_id) FROM devices) as total_devices,
        (SELECT count(distinct device_id) FROM measurements WHERE device_id NOT IN (SELECT device_id FROM devices)) as orphaned_measurements,
        (SELECT count(distinct device_id) FROM errors WHERE device_id NOT IN (SELECT device_id FROM devices)) as orphaned_errors,
        (SELECT count(distinct device_id) FROM devices WHERE device_id NOT IN (SELECT device_id FROM measurements)) as devices_without_telemetry
),

q1c_distributions AS (
    SELECT 
        firmware,
        network_type,
        region,
        count(*) as count_devices
    FROM devices
    GROUP BY 1, 2, 3
),

q1d_error_frequency AS (
    SELECT 
        error_code,
        count(*) as occurrences,
        count(distinct device_id) as unique_devices_affected
    FROM errors
    GROUP BY 1
    ORDER BY occurrences DESC
),

q1e_median_ping_interval AS (
    WITH ping_diffs AS (
        SELECT 
            device_id,
            timestamp,
            date_diff('second', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_seconds
        FROM measurements
    )
    SELECT 
        median(gap_seconds) as median_ping_seconds
    FROM ping_diffs
    WHERE gap_seconds IS NOT NULL
),

-- Question 2: Gap Analysis
gaps_base AS (
    SELECT 
        device_id,
        timestamp as current_ts,
        LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_ts,
        date_diff('minute', LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp), timestamp) as gap_minutes
    FROM measurements
),

long_gaps AS (
    -- Rule: Gap >= 2 days + nominal interval (5 mins)
    SELECT 
        device_id,
        prev_ts,
        current_ts,
        gap_minutes
    FROM gaps_base
    WHERE gap_minutes >= (2 * 24 * 60 + 5)
),

short_recurring_gaps AS (
    -- Rule: 3+ gaps >= 1 hour within a 7-day rolling window
    WITH gaps_filtered AS (
        SELECT 
            device_id,
            current_ts,
            gap_minutes
        FROM gaps_base
        WHERE gap_minutes >= 60
    ),
    rolling_counts AS (
        SELECT 
            device_id,
            current_ts,
            gap_minutes,
            count(*) OVER (
                PARTITION BY device_id 
                ORDER BY current_ts 
                RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW
            ) as gap_count_7d
        FROM gaps_filtered
    )
    SELECT DISTINCT device_id 
    FROM rolling_counts 
    WHERE gap_count_7d >= 3
),

q2_top_20_gap_devices AS (
    SELECT 
        device_id,
        SUM(gap_minutes) as total_gap_minutes
    FROM gaps_base
    WHERE current_ts >= (SELECT MAX(timestamp) - INTERVAL 30 DAYS FROM measurements)
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 20
),

-- Question 3 & 4: Profiling & Segmentation
problematic_devices AS (
    SELECT DISTINCT device_id, 'Long Gap' as issue_type FROM long_gaps
    UNION
    SELECT DISTINCT device_id, 'Short Recurring' as issue_type FROM short_recurring_gaps
),

segment_analysis AS (
    SELECT 
        d.*,
        p.issue_type,
        CASE WHEN p.device_id IS NOT NULL THEN 1 ELSE 0 END as is_problematic,
        e.error_count
    FROM devices d
    LEFT JOIN problematic_devices p ON d.device_id = p.device_id
    LEFT JOIN (SELECT device_id, count(*) as error_count FROM errors GROUP BY 1) e ON d.device_id = e.device_id
),

-- Question 5: Escalation
escalation_summary AS (
    SELECT 
        s.device_id,
        s.firmware,
        s.region,
        s.is_problematic,
        COALESCE(s.error_count, 0) as error_count,
        CASE 
            WHEN s.is_problematic = 1 AND s.error_count > 0 THEN 'High'
            WHEN s.is_problematic = 1 OR s.error_count > 5 THEN 'Medium'
            ELSE 'Low'
        END as priority
    FROM segment_analysis s
)

-- Final Outputs & Visualizations (Console-ready)

-- Console Chart: Error Frequency (Top 10)
SELECT 
    error_code,
    occurrences,
    repeat('█', (occurrences * 50 / (SELECT MAX(occurrences) FROM q1d_error_frequency))::INT) as chart
FROM q1d_error_frequency
LIMIT 10;

-- Console Chart: Escalation Priority Distribution
SELECT 
    priority,
    count(*) as count,
    repeat('█', (count(*) * 50 / (SELECT count(*) FROM escalation_summary))::INT) as chart
FROM escalation_summary
GROUP BY 1
ORDER BY count DESC;

-- Creating the escalation_list view as requested
CREATE OR REPLACE VIEW escalation_list AS 
SELECT * FROM escalation_summary WHERE priority IN ('High', 'Medium') ORDER BY priority, error_count DESC;

SELECT * FROM escalation_list;
