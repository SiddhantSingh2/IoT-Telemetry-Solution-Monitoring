# IoT Telemetry & Solution Monitoring Analysis

## Project Overview
This project provides a comprehensive SQL-based analysis of IoT device telemetry to identify connectivity gaps, firmware performance issues, and hardware errors. The solution is optimized for **DuckDB** and processes three primary datasets: device metadata, telemetry measurements, and error logs.

---

## Visual Insights

### 1. Error Frequency Analysis
Identifies the most common error codes across the fleet. `MissingData.Status` is the primary concern, indicating widespread telemetry loss.
![Error Frequency](error_frequency.png)

### 2. Fleet Escalation Priority
Distribution of devices categorized by health risk. High-priority devices require immediate technician intervention due to both gaps and active errors.
![Priority Distribution](priority_distribution.png)

### 3. Error Lift: Problematic vs. Healthy Fleet
Comparative analysis showing that devices with connectivity gaps (Problematic) have nearly **2x more errors** on average than the healthy fleet.
![Error Lift](error_lift_analysis.png)

---

## Technical Solution Overview (`iot_solution.sql`)
The final SQL solution is structured to handle massive telemetry datasets (including the 887 MB measurements file) efficiently using DuckDB's columnar engine.

### Key Analysis Sections:
1.  **Data Profiling**: Establishes baselines for data integrity, time horizons, and median ping intervals.
2.  **Gap Analysis**:
    *   **Long Gaps**: Silence period $\ge$ 2 days + 5 minutes.
    *   **Short Recurring Gaps**: 3+ gaps of $\ge$ 1 hour within a rolling 7-day window.
3.  **Lift Analysis**: Measures the concentration of error logs in problematic vs. healthy devices.
4.  **Escalation Logic**: Categorizes device health into High, Medium, and Low priority tiers.

---

## How to Run
1. **Run the SQL Analysis**:
   ```bash
   duckdb -c ".read iot_solution.sql"
   ```
2. **Generate Visualizations**:
   Ensure you have `pandas`, `matplotlib`, and `seaborn` installed, then run:
   ```bash
   python visualize_results.py
   ```

---

## Analysis Findings

### Hypotheses for Intermittent Behavior
*   **Firmware `v2.3.1` Network Stack**: High correlation between connectivity gaps and `MissingData` errors suggests a memory leak or network driver crash.
*   **Regional Thermal Throttling**: Devices in high-heat regions (south) show recurring gaps that may be related to hardware-level thermal protection.
*   **Cellular Handoff Failures**: Intermittent behavior in cellular devices points to potential tower-switching issues.

### Missing Data for Deeper Insights
*   **RSSI/SNR (Signal Strength)**: Crucial for distinguishing between "Offline" (power issue) and "Unreachable" (network issue).
*   **Internal Temperature Sensors**: To correlate environmental heat with hardware resets.
*   **Reboot Reason Codes**: To identify if devices are restarting due to a `Watchdog Timer` (crash).
