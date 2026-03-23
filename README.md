# IoT Telemetry & Solution Monitoring Analysis

## Project Overview
This analysis investigates intermittent connectivity issues and device health across a fleet of 800 IoT energy devices. The goal is to identify "at-risk" behavior, profile affected systems, and provide a prioritized escalation list for the operations team.

## Executive Summary
- **Primary Issue**: Intermittent "short recurring gaps" (>= 1 hour) are affecting **15.1% (121/800)** of the fleet.
- **Critical Correlation**: **100%** of flagged devices are running **firmware v2.3.1** and connect via **cellular** networks.
- **Geographic Clustering**: The **East region** is disproportionately affected (34.5% flagged rate).
- **Escalation**: **60 devices** are categorized as **High Priority** due to both connectivity gaps and active error logs.

---

## Part 1: Detailed Findings

### Question 1: Data Characterization
- **Time Coverage**:
    - Telemetry: 2025-12-23 to 2026-03-23 (3 months).
    - Errors: 2026-01-26 to 2026-03-20.
- **Scale**: 800 distinct devices, all of which appear in both telemetry and metadata. 439 devices (55%) have recorded errors.
- **Telemetry Cadence**: Nominal interval is **5 minutes**.
- **Common Errors**: `MissingData.Status` and `OtherError.0x100202` are the most frequent.

### Question 2: Connectivity Analysis
We defined two rules for "problematic" behavior:
1. **Long Gap**: >= 2 days (0 devices matched).
2. **Short Recurring Gaps**: >= 3 gaps of >= 1 hour in 7 days (**121 devices matched**).

**Top 5 Devices by Gap Minutes (Last 30 Days):**
| Device ID | Gap Events | Total Gap Min | Max Single Gap | Error Count |
|-----------|------------|---------------|----------------|-------------|
| IOT_EC1D6B9 | 29 | 5770 | 300 | 0 |
| IOT_CFB448F | 32 | 5765 | 285 | 6 |
| IOT_3AD643A | 29 | 5760 | 300 | 383 |
| IOT_BA07C15 | 31 | 5700 | 295 | 0 |
| IOT_5647899 | 30 | 5700 | 300 | 9 |

### Question 3: Profiling & Trends
- **Error Rates**: Flagged devices have **~2.2x higher error rates** (29.9 errors/sys) compared to healthy ones (13.3 errors/sys).
- **Trends**: Gap events have surged significantly starting in **March 2026**, suggesting a worsening network or firmware-related degradation.

### Question 4: Segmentation (The "Smoking Gun")
| Segment | Attribute | Flagged Rate |
|---------|-----------|--------------|
| **Firmware** | **v2.3.1** | **36.7%** (Other versions: 0%) |
| **Network** | **Cellular** | **36.3%** (Broadband/Fiber: 0%) |
| **Region** | **East** | **34.5%** |

**Conclusion**: The issue is exclusively isolated to **Cellular devices on Firmware v2.3.1**.

### Question 5: Escalation List
| Priority | Criteria | Count |
|----------|----------|-------|
| **High** | Flagged (Gaps) AND Errors > 0 | 60 |
| **Medium** | Flagged OR Errors > 5 | 373 |
| **Low** | All others with any error | 367 |

**Top 5 High Priority Escalations:**
1. **IOT_A955625** (1710 errors, Flagged)
2. **IOT_11D6914** (436 errors, Flagged)
3. **IOT_3AD643A** (386 errors, Flagged)
4. **IOT_02D3BA0** (339 errors, Flagged)
5. **IOT_5C41BBC** (120 errors, Flagged)

---

## Visualizations

### 1. Error Frequency (Top 10)
![Error Frequency](error_frequency.png)

### 2. Fleet Health Distribution
![Priority Distribution](priority_distribution.png)

### 3. Impact Analysis (Lift)
Flagged devices show a significant increase in error frequency compared to healthy ones.
![Error Lift](error_lift_analysis.png)

---

## Question 6: Reflection & Next Steps

### Additional Data Needed
- **Cellular Signal Strength (RSSI)**: To distinguish between firmware bugs and local tower issues.
- **Ambient Temperature**: To check for thermal throttling or hardware failures in specific regions.

### Hypotheses
1. **v2.3.1 Modem Driver Bug**: The 100% correlation with cellular/v2.3.1 suggests the new firmware might have a bug in handling cellular reconnection.
2. **Regional Carrier Degradation**: The clustering in the "East" region could point to a specific cellular provider's performance issues in that area.

### Alerts in Production
- **Risk**: Setting alerts on "Short Recurring Gaps" might trigger "flapping" notifications.
- **Iteration**: We should use a "sustained failure" window (e.g., 3 hours) before escalating to a human to reduce noise.

### Limitations
- Gaps are inferred from missing timestamps, not recorded disconnect events.
- Error codes are not categorized by severity (e.g., Critical vs Info), which may over-index certain devices.
