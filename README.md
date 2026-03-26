# IoT Telemetry & Solution Monitoring Analysis

This report provides a detailed analysis of the IoT device health and connectivity assignment. All findings are derived from SQL analysis of the telemetry, error, and device metadata.

---

## Question 1 – Understand the data

**Q1a. Time Coverage: Earliest and latest `timestamp` in telemetry and `start_time` in errors. What does the difference imply?**
- **Telemetry**: 2025-12-23 to 2026-03-23.
- **Errors**: 2026-01-26 to 2026-03-20.
- **Implication**: Error logs only cover the final ~2 months of the 3-month telemetry window. This means we cannot correlate connectivity gaps in early January with error logs, as they were not captured in this extract.

**Q1b. Scale: Count of distinct `device_id` in each file. Count of devices missing in telemetry vs attributes.**
- **Metadata**: 800 devices.
- **Telemetry**: 800 devices.
- **Errors**: 439 devices.
- **Gaps**: 0. The fleet is perfectly consistent across metadata and telemetry.

**Q1c. System Mix: Distribution by firmware, network, and region.**
- The fleet is spread across 4 regions (East is largest with 232 devices) and 3 network types (Broadband, Cellular, Fiber).

**Q1d. Errors: Distinct codes, frequency, and device counts.**
- **Distinct Error Codes**: 113.
- **Devices with at least one error**: 439.
- **Devices in telemetry with NO errors**: 361.
- **Frequency**: `MissingData.Status` is the top error code, appearing primarily in flagged devices.
![Error Frequency](error_frequency.png)

**Q1e. Telemetry Frequency: Infer the typical interval and note violations.**
- **Nominal Interval**: 5 minutes (confirmed by >20M instances).
- **Violations**: 121 devices show repeated violations of this 5-minute frequency, with gaps ranging from 60 minutes to several hours.

---

## Question 2 – Identify Connectivity Problems

**Q2a. Rule Application: How many devices satisfy Rule 1 (Long Gap >= 2 days) and Rule 2 (Short Recurring >= 3 gaps of 1hr in 7 days)?**
- **Rule 1 (Long Gap)**: 0 devices. No device has a single continuous outage of 2 days (2880 mins).
- **Rule 2 (Short Recurring)**: **121 devices**. This confirms the "intermittent" nature of the issue.

**Q2b. Top 20 Devices: Top 20 devices by total gap minutes in the last 30 days.**
- The top offenders are losing significant uptime. The list is dominated by devices on Cellular networks with high recurring downtime.

| device_id   |   gap_events |   total_gap_minutes |   max_single_gap_minutes |
|:------------|-------------:|--------------------:|-------------------------:|
| IOT_EC1D6B9 |           29 |                5770 |                      300 |
| IOT_3AD643A |           29 |                5760 |                      300 |
| IOT_BA07C15 |           31 |                5700 |                      295 |
| IOT_CFB448F |           31 |                5680 |                      285 |
| IOT_70DE115 |           29 |                5620 |                      280 |
| IOT_952AB7D |           30 |                5595 |                      295 |
| IOT_5647899 |           29 |                5560 |                      300 |
| IOT_CCD8F1C |           30 |                5560 |                      290 |
| IOT_3DF62EF |           30 |                5545 |                      300 |
| IOT_E7F8B70 |           29 |                5530 |                      290 |
| IOT_B148023 |           30 |                5505 |                      305 |
| IOT_BFC4A7C |           30 |                5495 |                      295 |
| IOT_1E86D82 |           30 |                5485 |                      270 |
| IOT_E15601B |           29 |                5455 |                      305 |
| IOT_EAA6C70 |           29 |                5450 |                      300 |
| IOT_E59788F |           28 |                5450 |                      290 |
| IOT_B1F517A |           28 |                5430 |                      270 |
| IOT_4DEA934 |           29 |                5415 |                      285 |
| IOT_3864140 |           28 |                5375 |                      300 |
| IOT_0E9A215 |           29 |                5360 |                      305 |

**Q2c. Consistency Check: Do error timing and telemetry gaps line up?**
- **Finding**: For the top 20 devices, there is a strong correlation. Devices like `IOT_3AD643A` show high error counts alongside massive gaps. However, some "silent failures" have zero errors despite large gaps, suggesting critical system crashes.

---

## Question 3 – Isolate and Profile the Affected Devices

**Q3a. Compare Installation Timing: Share of flagged devices by installation cohort.**
- **Analysis**: Flagged devices are spread across all installation periods. The issue is software/firmware related rather than a specific "bad batch" of older hardware.

![Installation Month Failure Rate](installation_month_q3a.png)
![Installation Year Failure Rate](installation_year_q3a.png)

**Q3b. Errors: Flagged vs Non-Flagged error rates.**
- **Flagged (Gaps)**: 29.89 errors per system.
- **Healthy (No Gaps)**: 13.29 errors per system.
- **Insight**: Problematic devices have **2.2x more errors** than healthy ones. 

| group_label |   systems |   errors_per_system |
|:------------|----------:|--------------------:|
| Healthy     |       679 |               13.29 |
| Flagged     |       121 |               29.89 |

![Error Lift](error_lift_analysis.png)

**Q3c. Extended Silence: Devices with no telemetry for > 24 hours.**
- **Finding**: 0 devices. No system has stayed offline for a full continuous 24-hour window (1440 mins). The modem always eventually reconnects.

**Q3d. Trend: Weekly total gap minutes for the top 10 devices.**
- **Trend**: Worsening. The volume of problematic gaps (>= 60 mins) has increased every week, peaking in March 2026. This indicates a progressive degradation rather than a stable issue.
![Top 10 Gap Trend](top_10_gap_trend_q3d.png)

**Which devices worry you most and what evidence supports that?**
The devices that worry me most are those on **Firmware v2.3.1 with Cellular connectivity**. This segment has a massive **92.37% failure rate**. Specifically, devices like `IOT_3AD643A` and `IOT_EC1D6B9` are losing over 5,700 minutes of telemetry monthly, representing a catastrophic loss of data visibility.

---

## Question 4 – Segmentation

**Q4a, b, c. Segmentation by Firmware, Network, and Region.**
- **Firmware**: V2.3.1 is the only version with significant connectivity failures.
- **Network**: Cellular is the only network type experiencing these recurring gaps.
- **Region**: The East region is the most heavily affected (34% failure rate).
![Firmware Segmentation](segmentation_firmware.png)
![Network Segmentation](segmentation_network.png)
![Region Segmentation](segmentation_region.png)

**Q4d. Installation Cohort: Share of flagged devices by installation month.**
![Installation Month Failure Rate](installation_month_q4d.png)

**Q4e. Strongest Pattern: Which segmentation best separates "High Concern" from "Typical"?**
- **The "Smoking Gun"**: The combination of **Firmware v2.3.1 and Cellular connectivity**.
- **Explanation**: This segment exhibits a **92.37% failure rate**, while all other firmware-network combinations (Fiber and Broadband) show a perfect **0.0% failure rate** for connectivity gaps. This proves the issue is a specific software regression in the v2.3.1 update affecting cellular modem drivers.

---

## Question 5 – Escalation List

**Q5a. Rules for Priority Levels.**
- **High**: Flagged (Rule 2 Gaps) AND active error logs (>0).
- **Medium**: Flagged (Gaps) OR frequent errors (>5).
- **Low**: Healthy (No gaps and minimal errors).

**Q5b. Priority Application: How many devices in each level?**
- **High**: 60 devices.
- **Medium**: 373 devices.
- **Low**: 367 devices.
![Priority Distribution](priority_distribution.png)

**Q5c. Top 20 Escalation List.**
The "Top 20" list is determined by filtering for the **High** priority group and sorting by **error_count DESC**. This prioritizes the systems experiencing the most severe combination of connectivity loss and internal software failures.

| device_id   | firmware   | network_type   |   error_count | priority   |
|:------------|:-----------|:---------------|--------------:|:-----------|
| IOT_A955625 | v2.3.1     | cellular       |          1710 | High       |
| IOT_11D6914 | v2.3.1     | cellular       |           436 | High       |
| IOT_3AD643A | v2.3.1     | cellular       |           386 | High       |
| IOT_02D3BA0 | v2.3.1     | cellular       |           339 | High       |
| IOT_5C41BBC | v2.3.1     | cellular       |           120 | High       |
| IOT_952AB7D | v2.3.1     | cellular       |            46 | High       |
| IOT_9264F38 | v2.3.1     | cellular       |            37 | High       |
| IOT_BE43A15 | v2.3.1     | cellular       |            25 | High       |
| IOT_BFC4A7C | v2.3.1     | cellular       |            21 | High       |
| IOT_6C56012 | v2.3.1     | cellular       |            21 | High       |
| IOT_B1F517A | v2.3.1     | cellular       |            19 | High       |
| IOT_9C7A38B | v2.3.1     | cellular       |            19 | High       |
| IOT_4DEA934 | v2.3.1     | cellular       |            16 | High       |
| IOT_F2828D9 | v2.3.1     | cellular       |            15 | High       |
| IOT_0E9A215 | v2.3.1     | cellular       |            15 | High       |
| IOT_15BD259 | v2.3.1     | cellular       |            14 | High       |
| IOT_B9B8E12 | v2.3.1     | cellular       |            14 | High       |
| IOT_73D748C | v2.3.1     | cellular       |            14 | High       |
| IOT_4903FF9 | v2.3.1     | cellular       |            13 | High       |
| IOT_6E1F2CA | v2.3.1     | cellular       |            13 | High       |

**Q5d. Edge Case: Long absence but NO error rows.**
- **Count**: **61 devices** have gaps but NO errors.
- **Treatment**: These land in the **Medium** priority bucket as they are likely experiencing "total system crashes" that prevent error logging.

**Q5e. Timing: Is there a week where behavior first shows unusual gaps?**
- **Finding**: Connectivity issues spiked dramatically starting the week of March 9th, 2026.
![Gap Trend](gap_trend.png)

---

## Question 6 – Written Reflection

**a. What additional data (not in these files) would most improve root-cause confidence? List a few concrete examples.**
To move from "guessing" to "knowing" the cause, I would look for:
- **Cellular Signal Strength:** This would tell us if the devices are just in "dead zones" with bad reception or if the hardware inside the box is actually failing.
- **Internal Reboot Logs:** These logs would show us if the device is crashing because it ran out of memory or if the modem is just timing out and giving up.
- **Cell Tower Maintenance:** Cross referencing our outages with 4G/5G tower downtime would help us rule out external network problems that we can't control.

**b. State at least two plausible hypotheses for what might drive intermittent behavior in the field. For each: what in your analysis supports or weakens it, and what data would falsify it?**
1. **A bug in the v2.3.1 update:** This is the "smoking gun." Since 92.3% of devices on this specific version and network are struggling, it’s almost certainly a mistake in the new code. It likely broke the way the device talks to cellular networks.
    - **How to disprove:** If we find devices on the old software having the same problems, then the update isn't the problem—the network is.
2. **Memory Leaks:** It’s possible the systems are slowly filling up their internal storage until they "choke" and restart. This explains why the gaps seem to get worse the longer the devices are in the field.
    - **How to disprove:** If we put the same heavy data load on a Fiber-connected device and it stays stable, then the issue is unique to how the cellular modems handle their tasks.

**c. If your Q5 rules were turned into production alerts, what could go wrong, and how would you iterate with stakeholders?**
The biggest risk is "Alert Fatigue", we don't want to have an alert every time a device has a 5-minute gap.
- **Wait and see:** Instead of alerting the second a device misses one ping, we should only trigger an alarm if it meets the "3 gaps in 7 days" rule. This ignores "noisy" but healthy devices.
- **Make them useful:** An alert shouldn't just say "Offline." It should tell the tech exactly what to do, like: "Likely software bug — recommend remote rollback to v2.3.0."

**d. What limitations of these extracts should a non-technical audience hear before acting on your numbers?**
- **The "Missing" Log Problem:** The error logs don't cover the whole year, so we might have missed the very first signs of trouble from early January.
- **Unmapped Error Codes:** Several logs contain raw numeric codes without descriptions. Without a data dictionary to translate these, field technicians cannot know if a code represents a minor glitch or a total hardware failure.
- **Data isn't proof:** Even though the stats point a finger at version v2.3.1, we shouldn't start a massive hardware recall until we've tested this in a lab.
- **The "Silent Failures":** There are 61 devices that are dropping data but aren't even healthy enough to log an error. This means the situation is actually more serious than the error counts suggest—some devices are "crashing out" completely.
