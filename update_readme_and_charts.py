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

    # --- TABLES ---
    
    # Q2b: Top 20 Gaps Table
    print("Extracting Q2b Table...")
    top_20_gaps = con.execute("SELECT * FROM top_20_gaps").df()
    top_20_gaps_md = top_20_gaps.to_markdown(index=False)

    # Q5c: Top 20 Escalation Table
    print("Extracting Q5c Table...")
    top_20_escalation = con.execute("SELECT * FROM top_20_escalation").df()
    top_20_escalation_md = top_20_escalation.to_markdown(index=False)

    # Q4d: Installation Cohort (Month)
    print("Extracting Q4d Table...")
    q4_d_data = con.execute("""
        SELECT 
            date_trunc('month', install_date) as install_month,
            count(*) as total_devices,
            count(p.device_id) as flagged_devices,
            round(count(p.device_id) * 100.0 / count(*), 2) as failure_rate
        FROM devices d
        LEFT JOIN problematic_devices p ON d.device_id = p.device_id
        GROUP BY 1 ORDER BY 1
    """).df()
    q4_d_md = q4_d_data.to_markdown(index=False)

    # Q3b: Errors per system per week
    # Assuming 8 weeks of error data based on Q1a
    print("Calculating Q3b metrics...")
    q3_b_data = con.execute("SELECT * FROM q3_b_error_comparison").df()
    q3_b_data['errors_per_system_per_week'] = q3_b_data['errors_per_system'] / 8.0
    q3_b_md = q3_b_data.to_markdown(index=False)

    # --- GRAPHS ---

    # Q3a/Q4d: Failure Rate by Installation Month
    print("Generating Installation Month Graph...")
    plt.figure(figsize=(12, 6))
    sns.barplot(data=q4_d_data, x='install_month', y='failure_rate', palette=PALETTE)
    plt.title('Failure Rate by Installation Month (Q3a / Q4d)', fontsize=16)
    plt.xticks(rotation=45)
    plt.ylabel('Flagged Device %')
    plt.tight_layout()
    plt.savefig('installation_month_failure.png')
    plt.close()

    # Q3a: Failure Rate by Installation Year
    print("Generating Installation Year Graph...")
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
    plt.title('Failure Rate by Installation Year (Q3a)', fontsize=16)
    plt.ylabel('Flagged Device %')
    plt.savefig('installation_year_failure.png')
    plt.close()

    # Q3d: Weekly Trend for Top 10
    print("Generating Q3d Trend Graph...")
    q3_d_data = con.execute("SELECT * FROM top_10_weekly_trend").df()
    plt.figure(figsize=(12, 6))
    sns.lineplot(data=q3_d_data, x='week', y='weekly_gap_minutes', hue='device_id', marker='o')
    plt.title('Weekly Gap Minutes Evolution - Top 10 Devices (Q3d)', fontsize=16)
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig('top_10_gap_trend.png')
    plt.close()

    # --- SAVE DATA FOR README ---
    with open('readme_updates.txt', 'w') as f:
        f.write("### Q2b Table\n")
        f.write(top_20_gaps_md + "\n\n")
        f.write("### Q5c Table\n")
        f.write(top_20_escalation_md + "\n\n")
        f.write("### Q4d Table\n")
        f.write(q4_d_md + "\n\n")
        f.write("### Q3b Table\n")
        f.write(q3_b_md + "\n\n")

    print("Success! Tables and charts generated.")

if __name__ == "__main__":
    generate_updates()
