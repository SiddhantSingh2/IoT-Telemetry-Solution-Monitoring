import duckdb
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Set visual style
sns.set_theme(style="whitegrid")
plt.rcParams['figure.figsize'] = (12, 6)

def generate_charts():
    # Connect to DuckDB
    con = duckdb.connect(database=':memory:')
    
    # Run the SQL solution to populate views/tables
    print("Executing SQL Solution...")
    with open('iot_solution.sql', 'r') as f:
        sql_script = f.read()
        # Split script by semicolon to execute one by one (DuckDB requirement for multiple statements)
        for statement in sql_script.split(';'):
            if statement.strip():
                con.execute(statement)

    # 1. Error Frequency Chart
    print("Generating Error Frequency Chart...")
    error_freq = con.execute("""
        SELECT error_code, count(*) as occurrences 
        FROM errors 
        GROUP BY 1 
        ORDER BY 2 DESC 
        LIMIT 10
    """).df()
    
    plt.figure(figsize=(12, 6))
    sns.barplot(data=error_freq, x='occurrences', y='error_code', palette='viridis')
    plt.title('Top 10 IoT Device Error Codes', fontsize=16)
    plt.tight_layout()
    plt.savefig('error_frequency.png')
    plt.close()

    # 2. Priority Distribution
    print("Generating Priority Distribution Chart...")
    priority_dist = con.execute("SELECT priority, count(*) as count FROM escalation_list GROUP BY 1").df()
    
    # Add Low priority back for a complete view
    low_priority = con.execute("""
        SELECT 'Low' as priority, count(*) as count 
        FROM (
            SELECT *, CASE 
                WHEN is_problematic = 1 AND error_count > 0 THEN 'High' 
                WHEN is_problematic = 1 OR error_count > 5 THEN 'Medium' 
                ELSE 'Low' 
            END as priority 
            FROM segmentation
        ) WHERE priority = 'Low'
    """).df()
    
    full_dist = pd.concat([priority_dist, low_priority])
    
    plt.figure(figsize=(8, 8))
    colors = sns.color_palette('pastel')[0:3]
    plt.pie(full_dist['count'], labels=full_dist['priority'], autopct='%1.1f%%', colors=['#ff9999','#66b3ff','#99ff99'], startangle=140)
    plt.title('IoT Fleet Escalation Priority Distribution', fontsize=16)
    plt.savefig('priority_distribution.png')
    plt.close()

    # 3. Lift Analysis Chart
    print("Generating Lift Analysis Chart...")
    lift_data = con.execute("""
        SELECT 
            CASE WHEN is_problematic = 1 THEN 'Problematic Segment' ELSE 'Healthy Segment' END as segment,
            AVG(error_count) as avg_errors
        FROM segmentation
        GROUP BY 1
    """).df()

    plt.figure(figsize=(10, 6))
    sns.barplot(data=lift_data, x='segment', y='avg_errors', palette='magma')
    plt.title('Average Errors: Problematic vs Healthy Fleet', fontsize=16)
    plt.ylabel('Average Error Count')
    plt.savefig('error_lift_analysis.png')
    plt.close()

    print("Success! Charts saved as PNG files.")

if __name__ == "__main__":
    generate_charts()
