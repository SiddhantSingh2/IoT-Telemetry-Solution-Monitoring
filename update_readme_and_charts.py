import duckdb
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Set visual style
sns.set_theme(style="whitegrid")
plt.rcParams['figure.figsize'] = (12, 6)
PALETTE = 'viridis'

def generate_updates():
    # Connect to DuckDB
    con = duckdb.connect(database=':memory:')
    
    print("Executing SQL Solution...")
    with open('iot_solution.sql', 'r') as f:
        sql_script = f.read()
        con.execute(sql_script)

    # --- DATA EXTRACTION ---
    
    # Q4d/Q3a Data
    q4_d_data = con.execute("""
        SELECT 
            strftime(install_date, '%Y-%m') as install_month_str,
            count(*) as total_devices,
            count(p.device_id) as flagged_devices,
            round(count(p.device_id) * 100.0 / count(*), 2) as failure_rate
        FROM devices d
        LEFT JOIN problematic_devices p ON d.device_id = p.device_id
        GROUP BY 1 ORDER BY 1
    """).df()

    # --- GRAPHS ---

    # Q3a: Failure Rate by Installation Month (Title: Question 3a)
    print("Generating Q3a Installation Month Graph...")
    plt.figure(figsize=(14, 7))
    sns.barplot(data=q4_d_data, x='install_month_str', y='failure_rate', palette=PALETTE)
    plt.title('Share of Flagged Devices by Installation Month (Question 3a)', fontsize=16)
    plt.xticks(rotation=90)
    plt.ylabel('Failure Rate (%)')
    plt.tight_layout()
    plt.savefig('installation_month_q3a.png')
    plt.close()

    # Q4d: Failure Rate by Installation Month (Title: Question 4d)
    print("Generating Q4d Installation Month Graph...")
    plt.figure(figsize=(14, 7))
    sns.barplot(data=q4_d_data, x='install_month_str', y='failure_rate', palette=PALETTE)
    plt.title('Segmentation by Installation Cohort (Question 4d)', fontsize=16)
    plt.xticks(rotation=90)
    plt.ylabel('Failure Rate (%)')
    plt.tight_layout()
    plt.savefig('installation_month_q4d.png')
    plt.close()

    # Q3a: Failure Rate by Installation Year
    print("Generating Q3a Installation Year Graph...")
    q3_a_year = con.execute("""
        SELECT 
            date_part('year', install_date) as install_year,
            count(*) as total_fleet,
            count(p.device_id) as flagged_count,
            round(count(p.device_id) * 100.0 / count(*), 2) as failure_rate
        FROM devices d
        LEFT JOIN problematic_devices p ON d.device_id = p.device_id
        GROUP BY 1 ORDER BY 1
    """).df()
    plt.figure(figsize=(10, 6))
    sns.barplot(data=q3_a_year, x='install_year', y='failure_rate', palette=PALETTE)
    plt.title('Failure Rate by Installation Year (Question 3a)', fontsize=16)
    plt.ylabel('Failure Rate (%)')
    plt.tight_layout()
    plt.savefig('installation_year_q3a.png')
    plt.close()

    # Q3d: Weekly Trend for Top 10
    print("Generating Q3d Trend Graph...")
    q3_d_data = con.execute("SELECT * FROM top_10_weekly_trend").df()
    plt.figure(figsize=(12, 6))
    sns.lineplot(data=q3_d_data, x='week', y='weekly_gap_minutes', hue='device_id', marker='o')
    plt.title('Weekly Gap Minutes Evolution - Top 10 Devices (Question 3d)', fontsize=16)
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig('top_10_gap_trend_q3d.png')
    plt.close()

    # Get Dec 2021 specifically for the text update
    dec_2021 = q4_d_data[q4_d_data['install_month_str'] == '2021-12']
    print(f"Dec 2021 Data:\n{dec_2021}")
    
    # Find month with most flagged devices
    most_flagged_month = q4_d_data.loc[q4_d_data['flagged_devices'].idxmax()]
    print(f"Month with most flagged devices: {most_flagged_month['install_month_str']} ({most_flagged_month['flagged_devices']} devices)")

    print("Success! Updated charts generated.")

if __name__ == "__main__":
    generate_updates()
