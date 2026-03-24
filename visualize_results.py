import duckdb
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Set visual style
sns.set_theme(style="whitegrid")
plt.rcParams['figure.figsize'] = (12, 6)
PALETTE = 'viridis'

def generate_charts():
    # Connect to DuckDB
    con = duckdb.connect(database=':memory:')
    
    # Run the SQL solution to populate views/tables
    print("Executing SQL Solution...")
    with open('iot_solution.sql', 'r') as f:
        sql_script = f.read()
        # Clean the script for duckdb execution
        con.execute(sql_script)

    # 1. Error Frequency Chart (Q1d)
    print("Generating Error Frequency Chart...")
    error_freq = con.execute("""
        SELECT error_code, count(*) as occurrences 
        FROM errors 
        GROUP BY 1 
        ORDER BY 2 DESC 
        LIMIT 10
    """).df()
    
    plt.figure(figsize=(12, 6))
    sns.barplot(data=error_freq, x='occurrences', y='error_code', palette=PALETTE)
    plt.title('Top 10 IoT Device Error Codes (Question 1d)', fontsize=16)
    plt.tight_layout()
    plt.savefig('error_frequency.png')
    plt.close()

    # 2. Priority Distribution (Q5b)
    print("Generating Priority Distribution Chart...")
    priority_dist = con.execute("SELECT priority, count(*) as count FROM fleet_priority GROUP BY 1 ORDER BY 1").df()
    
    plt.figure(figsize=(8, 8))
    viridis_colors = sns.color_palette(PALETTE, n_colors=len(priority_dist))
    plt.pie(priority_dist['count'], labels=priority_dist['priority'], autopct='%1.1f%%', colors=viridis_colors, startangle=140)
    plt.title('IoT Fleet Escalation Priority Distribution (Question 5b)', fontsize=16)
    plt.savefig('priority_distribution.png')
    plt.close()

    # 3. Lift Analysis Chart (Q3b)
    print("Generating Lift Analysis Chart...")
    lift_data = con.execute("SELECT * FROM q3_b_error_comparison").df()

    plt.figure(figsize=(10, 6))
    sns.barplot(data=lift_data, x='status', y='errors_per_system', palette=PALETTE)
    plt.title('Average Errors: Flagged vs Healthy Fleet (Question 3b)', fontsize=16)
    plt.ylabel('Average Error Count')
    plt.savefig('error_lift_analysis.png')
    plt.close()

    # 4. Segmentation: Firmware (Q4a)
    print("Generating Firmware Segmentation Chart...")
    firmware_data = con.execute("""
        SELECT firmware, 
               round(count(CASE WHEN device_id IN (SELECT device_id FROM problematic_devices) THEN 1 END) * 100.0 / count(*), 1) as failure_rate
        FROM devices
        GROUP BY 1 ORDER BY 2 DESC
    """).df()

    plt.figure(figsize=(10, 6))
    sns.barplot(data=firmware_data, x='firmware', y='failure_rate', palette=PALETTE)
    plt.title('Failure Rate by Firmware Version (Question 4a)', fontsize=16)
    plt.ylabel('Flagged Device %')
    plt.savefig('segmentation_firmware.png')
    plt.close()

    # 5. Segmentation: Network (Q4b)
    print("Generating Network Segmentation Chart...")
    network_data = con.execute("""
        SELECT network_type, 
               round(count(CASE WHEN device_id IN (SELECT device_id FROM problematic_devices) THEN 1 END) * 100.0 / count(*), 1) as failure_rate
        FROM devices
        GROUP BY 1 ORDER BY 2 DESC
    """).df()

    plt.figure(figsize=(10, 6))
    sns.barplot(data=network_data, x='network_type', y='failure_rate', palette=PALETTE)
    plt.title('Failure Rate by Network Type (Question 4b)', fontsize=16)
    plt.ylabel('Flagged Device %')
    plt.savefig('segmentation_network.png')
    plt.close()

    # 6. Gap Events Trend (Q5e)
    print("Generating Gap Trend Chart...")
    trend_data = con.execute("""
        SELECT date_trunc('week', current_ts) as week, count(*) as gap_events
        FROM gaps_base WHERE gap_minutes >= 65
        GROUP BY 1 ORDER BY 1
    """).df()

    plt.figure(figsize=(12, 6))
    sns.lineplot(data=trend_data, x='week', y='gap_events', marker='o', color='#21918c')
    plt.title('Connectivity Gap Events Trend (Question 5e)', fontsize=16)
    plt.ylabel('Count of Gap Events (>=1hr)')
    plt.tight_layout()
    plt.savefig('gap_trend.png')
    plt.close()

    # 7. Segmentation: Region (Q4c)
    print("Generating Regional Segmentation Chart...")
    region_data = con.execute("SELECT * FROM q4_c_region").df()
    plt.figure(figsize=(10, 6))
    sns.barplot(data=region_data, x='region', y='failure_rate', palette=PALETTE)
    plt.title('Failure Rate by Region (Question 4c)', fontsize=16)
    plt.ylabel('Flagged Device %')
    plt.savefig('segmentation_region.png')
    plt.close()

    print("Success! All charts saved as PNG files.")

if __name__ == "__main__":
    generate_charts()
