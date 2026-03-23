# IoT Telemetry & Solution Monitoring Analysis

This document provides a comprehensive analysis of the IoT device health and connectivity assignment. All findings are derived from SQL analysis on the provided telemetry, error, and device metadata.

---

## Part 1: Detailed Findings by Question

### Question 1: Understand the Data
**a. Time Coverage**
- **Telemetry**: 2025-12-23 to 2026-03-23.
- **Errors**: 2026-01-26 to 2026-03-20.
- *Implication*: Error logs cover a shorter window (~2 months) within the 3-month telemetry period. Joining them requires filtering for overlapping periods to avoid under-counting healthy systems in early January.

**b. Scale**
- **Distinct Devices**: 800 in metadata, 800 in telemetry, 439 in errors.
- **Join Gaps**: 0 (Full consistency between files).

**c. System Mix**
- Fleet is diverse across 6 firmware versions and 3 network types (Cellular, Broadband, Fiber).

**d. Errors & Cadence**
- **Distinct Error Codes**: 113.
- **Telemetry Cadence**: Nominal interval is **5 minutes** (median/mode gap).

**Visual Analysis (Q1d):**
The chart below shows the top 10 error codes. `MissingData.Status` is the most frequent, which aligns with the reported connectivity issues.
![Error Frequency](error_frequency.png)

---

### Question 2: Identify Connectivity Problems
**a. Rule Application**
- **Long Gap (Rule 1)**: >= 2 days (0 devices).
- **Short Recurring Gaps (Rule 2)**: >= 3 gaps of >= 1 hour in 7 days (**121 devices**).

**b. Top 20 Devices (Last 30 Days)**
The top 20 devices by gap minutes are listed in the SQL output (`top_20_gaps` table). Most have accumulated >5,000 gap minutes in the final month.

---

### Question 3: Isolate and Profile Affected Devices
**a. Installation Timing**
- No significant clustering by installation date was found once the date format was correctly parsed; failure rates are consistent across install cohorts.

**b. Error Comparison**
Flagged devices show a significant "lift" in error frequency.
- **Flagged Group**: 29.9 errors per system.
- **Healthy Group**: 13.3 errors per system.

**Visual Analysis (Q3b):**
This graph demonstrates that problematic devices have over **2x more errors** on average than the rest of the fleet.
![Error Lift](error_lift_analysis.png)

---

### Question 4: Segmentation
**a & b. Firmware and Network Patterns**
The data shows an absolute correlation between failure and specific attributes.

**Visual Analysis (Q4a & Q4b):**
As shown below, **Firmware v2.3.1** and **Cellular** networks are the only segments experiencing these recurring gaps.

![Firmware Segmentation](segmentation_firmware.png)
![Network Segmentation](segmentation_network.png)

**e. Strongest Pattern**
The single strongest segmentation is the combination of **Firmware v2.3.1 + Cellular**. This segment has a **36% failure rate**, while every other combination in the fleet has a **0% failure rate**.

---

### Question 5: Escalation List
**a & b. Priority Rules**
- **High**: Flagged (Gaps) AND active errors (>0). (**60 devices**).
- **Medium**: Flagged OR frequent errors (>5). (**373 devices**).
- **Low**: Minimal errors and no gaps. (**367 devices**).

**Visual Analysis (Q5b):**
Distribution of the prioritized fleet health. (Note: Palette corrected to ensure consistency).
![Priority Distribution](priority_distribution.png)

**e. Trend Analysis**
Connectivity gaps have worsened significantly over time, peaking in the final week of March 2026.

**Visual Analysis (Q5e):**
![Gap Trend](gap_trend.png)

---

### Question 6: Written Reflection
- **Additional Data**: RSSI (Signal strength) and Watchdog reset logs would confirm if this is a modem crash or tower issue.
- **Hypotheses**: 
    1. **Firmware v2.3.1 Bug**: Likely a memory leak or driver crash in the cellular stack.
    2. **Regional Network Degradation**: Worsening trend suggests a localized network issue or rolling firmware update causing congestion.
- **Alerting Risks**: "Short recurring" rules can be noisy; recommend using a "time-to-recover" threshold to filter transient blips.
- **Limitations**: Inferred gaps may include intentional maintenance windows; severity of error codes is unknown.
