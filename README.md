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
- The top offenders are losing roughly 10-15% of their expected uptime. The list is dominated by devices on Cellular networks with high recurring downtime.

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
| IOT_2454CA4 |           30 |                5360 |                      300 |

**Q2c. Consistency Check: Do error timing and telemetry gaps line up?**
- **Finding**: For the top 20 devices, there is a strong correlation. Devices like `IOT_3AD643A` show 382 error logs alongside 5,760 minutes of gaps. However, some devices like `IOT_EC1D6B9` have massive gaps but **zero** error logs, suggesting the "MissingData" error isn't always logged when the cellular modem crashes.

---

## Question 3 – Isolate and Profile the Affected Devices

**Q3a. Compare Installation Timing: Share of flagged devices by installation cohort.**
- **Analysis**: Flagged devices are spread across all installation periods. While early small cohorts (Jan/Oct 2020) show 100% failure rates due to sample size, the most significant volume of failures comes from the **December 2024 cohort (12 flagged devices)**. The December 2021 cohort also remains a high-risk group with a **42.86% failure rate**. This broad distribution across years suggests the issue is software/firmware related rather than a hardware-aging batch.

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
- **Finding**: 0 devices. While Rule 2 is heavily triggered, no device has stayed offline for a full continuous 24-hour window (1440 mins). The modem always manages to reconnect eventually.

**Q3d. Trend: Weekly total gap minutes for the top 10 devices.**
- **Trend**: Worsening. The total volume of gap minutes has increased every week through March 2026, peaking in the final week of the telemetry file.
![Top 10 Gap Trend](top_10_gap_trend_q3d.png)

**Which devices worry you most and what evidence supports that?**
The devices that worry me most are the **High Priority** devices on **Firmware v2.3.1 with Cellular connectivity**. Specifically, the **92.37% failure rate** within this segment (121 out of 131 devices) is a definitive indicator of a critical firmware regression. Devices like `IOT_3AD643A` and `IOT_EC1D6B9` are the highest concern as they lose over **5,700 minutes of telemetry per month**, representing a catastrophic loss of data for monitoring energy production and grid stability.

---

## Question 4 – Segmentation

**Q4a, b, c. Segmentation by Firmware, Network, and Region.**
- **Firmware**: V2.3.1 is the only version failing.
- **Network**: Cellular is the only network type failing.
- **Region**: The East region is the most heavily affected (34% failure rate).
![Firmware Segmentation](segmentation_firmware.png)
![Network Segmentation](segmentation_network.png)
![Region Segmentation](segmentation_region.png)

**Q4d. Installation Cohort: Share of flagged devices by installation month.**
- The failures cluster in the December 2024 cohort in terms of volume, but the failure rate is consistently high for Cellular/v2.3.1 devices regardless of their specific installation month.
![Installation Month Failure Rate](installation_month_q4d.png)

**Q4e. Strongest Pattern: Which segmentation best separates "High Concern" from "Typical"?**
- **One Paragraph Explanation**: The single segmentation that best separates "high concern" from "typical" is the intersection of **Firmware v2.3.1 and Cellular connectivity**. This segment exhibits a massive **92.37% failure rate** compared to the rest of the fleet, which shows a perfect **0.0% failure rate** for all other firmware-network combinations (Fiber and Broadband). This indicates that the connectivity issue is a specific software-driver regression in the v2.3.1 update affecting cellular modems, rather than a hardware-aging problem or a regional network outage.

---

## Question 5 – Escalation List

**Q5a. Rules for Priority Levels.**
- **High**: Flagged (Rule 2 Gaps) AND active error logs (>0). These are systems failing and actively reporting issues.
- **Medium**: Flagged (Gaps) OR frequent errors (>5). This catches "silent failures" (gaps but no errors) and unstable but connected systems.
- **Low**: Healthy (No gaps and minimal errors).

**Q5b. Priority Application: How many devices in each level?**
- **High**: 60 devices (7.5%)
- **Medium**: 373 devices (46.6%)
- **Low**: 367 devices (45.9%)
![Priority Distribution](priority_distribution.png)

**Q5c. Top 20 Escalation List.**
The "Top 20" list is determined by first filtering for the highest priority bucket (**High**) and then sorting by **error_count DESC**. This ensures we escalate the "sickest" devices first—those that are both losing significant data and experiencing the highest volume of internal software failures.

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
| IOT_9C7A38B | v2.3.1     | cellular       |            19 | High       |
| IOT_B1F517A | v2.3.1     | cellular       |            19 | High       |
| IOT_4DEA934 | v2.3.1     | cellular       |            16 | High       |
| IOT_F2828D9 | v2.3.1     | cellular       |            15 | High       |
| IOT_0E9A215 | v2.3.1     | cellular       |            15 | High       |
| IOT_15BD259 | v2.3.1     | cellular       |            14 | High       |
| IOT_73D748C | v2.3.1     | cellular       |            14 | High       |
| IOT_B9B8E12 | v2.3.1     | cellular       |            14 | High       |
| IOT_DC48471 | v2.3.1     | cellular       |            13 | High       |
| IOT_6E1F2CA | v2.3.1     | cellular       |            13 | High       |

**Q5d. Edge Case: Long absence but NO error rows.**
- **Count**: **61 devices** have connectivity gaps but NO error logs in the `iot_device_errors` file.
- **Treatment**: These land in the **Medium** priority group (unless they have massive gaps, in which case they may still be manually flagged). The absence of errors likely indicates the system crashed so hard it couldn't even log its own failure before going offline.

**Q5e. Timing: Is there a week where behavior first shows unusual gaps?**
- **Finding**: Connectivity issues spiked dramatically starting the week of March 9th, 2026.
![Gap Trend](gap_trend.png)

---

## Question 6 – Written Reflection

**a. What extra information would help us be more certain?**
To really pin down the root cause, I’d love to see a few things that weren't in this dataset. First, **signal strength data (like RSSI)** would tell us if these devices are just in "dead zones" or if the hardware is actually failing. Second, having **internal reboot logs** would be huge—it would show us if the device is crashing because of a "memory leak" or if the modem is just timing out. Finally, knowing if there was any **scheduled maintenance** from the cellular providers would help us rule out external network issues that have nothing to do with our equipment.

**b. What are the most likely theories for why this is happening?**
1. **A bug in the v2.3.1 firmware update:** This is the most likely culprit. Since nearly every device (92.37%) on this specific version and network type is struggling, it looks like a software "regression." Basically, the new code might not know how to talk to cellular modems properly. We could disprove this by checking if any devices on older firmware are having the same issues; if they aren't, the update is definitely to blame.
2. **The devices are "running out of breath" (Resource Leaks):** It's possible the systems are slowly filling up their internal memory until they can't handle any more data, which causes them to "hiccup" or restart. This would explain why the gaps seem to be getting worse the longer the devices are in the field. We could test this by trying to force a crash on a broadband device using the same data load; if it stays stable, the issue is specific to how the cellular modems handle resources.

**c. What should we keep in mind if we turn these into automatic alerts?**
The biggest risk is "alert fatigue"—we don't want to "cry wolf" every time a device has a minor connection blip. If we set the thresholds too tight, the operations team will start ignoring the notifications. To fix this, I’d suggest adding a "wait and see" period. Instead of alerting the second a device misses a few pings, we should wait to see if it stays problematic for a couple of days. We also need to make sure the alerts are actually helpful, giving the team a clear next step like "Roll back firmware to v2.3.0."

**d. A few things the broader team should know about this data:**
It’s important to be honest about the limits of what we’re looking at. For one, the **error logs are shorter than the telemetry data**, so we might be missing the very first signs of trouble from earlier in the year. Also, even though the stats point a finger at the v2.3.1 update, **correlation doesn't always equal causation**. It’s a very strong lead, but we should verify it in a lab before we start a massive recall. Lastly, there are over 60 devices that are "silent failures"—they're dropping data but aren't even healthy enough to log an error. This means the problem might be even more serious than the error counts suggest.
