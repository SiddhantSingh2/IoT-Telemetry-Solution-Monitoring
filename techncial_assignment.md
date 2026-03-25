# Solution Monitoring – Technical Assignment
### Data Analyst Candidate Evaluation | IoT Device Health & Connectivity

**Audience:** Data Analyst / BI candidate
**Domain:** IoT device health, connectivity monitoring

---

## Welcome

Thank you for participating in our technical assignment.

This exercise reflects the kind of work you would do on our **Solution Monitoring** team. We monitor the health, connectivity, and performance of thousands of IoT energy devices installed at customer sites. When something goes wrong in the field, the data analyst’s job is to find it in the data, size it, explain it, and communicate clearly to technical and non-technical stakeholders.

The assignment is structured in **two parts**:

| Part | Format | Focus |
|------|--------|-------|
| **Part 1** | Take-home (this document) | Data exploration, SQL analysis, written findings |
| **Part 2** | Live session (~60 min) | Walk through your solution, discuss your approach, defend your choices |

You are currently working on **Part 1**.

> **Important:** There are no trick questions. We care about how you structure the problem, what you check in the data, how you justify thresholds, and how clearly you present conclusions.

---

## Background / Scenario

The operations team has an informal concern:

> *"Some devices seem to come and go — not a clean long outage, but intermittent. We are not sure how big it is, whether it clusters anywhere, or which devices we should look at first. There is no formal ticket log in what you receive. Please use the data we give you to say whether there is a real issue, how serious it is, and what you would recommend next."*

**You do not receive incident or ticket data.** Work from the files described below only.

By the end of Part 1, your write-up should let a reader understand:

1. What time period the data covers and how complete it is.
2. How you defined “problematic” or “at risk” behavior and how many devices match.
3. Whether patterns appear by firmware, network, region, installation timing, or error codes.
4. Which devices you would prioritize for follow-up and why.
5. What is missing from the data that would strengthen root-cause conclusions.

---

## Data You Receive

You receive three tables. The logical names below describe the content.

---
### 1. `iot_devices`


One row per system.

| Column | Description |
|--------|-------------|
| `device_id` | device identifier |
| `firmware` | Firmware version label in effect for this export |
| `network_type` | How the site connects (e.g. cellular, broadband, fiber) |
| `region` | Geographic region label |
| `installation_date` | When the system was installed (format as provided) |



---
### 2. `iot_measurements`


One row per reading, per system.

| Column | Description |
|--------|-------------|
| `device_id` | device identifier |
| `timestamp` | When the reading was recorded (UTC unless stated otherwise) |
| `voltage_v` | Measured voltage |
| `current_a` | Measured current |

Readings are expected at a **regular interval** (you should infer the nominal interval from the data). **Missing timestamps** (gaps between consecutive readings longer than the nominal interval) indicate periods when the system did not report telemetry.

---

### 3. `iot_devices_errors`

One row per error event (not every system appears in every time window).

| Column | Description |
|--------|-------------|
| `device_id` | device identifier |
| `error_code` | Error identifier (numeric or text, as provided) |
| `start_time` | When the error was first seen |
| `last_seen_at` | Last observation of that error instance (may equal `start_time`) |

There is **no separate severity or category column** in this extract. If you need groupings, derive them from `error_code` (e.g. patterns in the code values or string prefixes) and state your assumptions.

---

## How to Work With the Data

Use **SQL** on any platform you are comfortable with (e.g. Snowflake, BigQuery, DuckDB, SQL Server). Load the provided CSV files as tables in your environment and reference them using the logical names below. Join across all three files on `device_id`.

Below is a **reference** starting block; adjust the table paths to match your platform.

```sql
WITH iot_devices AS (
    SELECT * FROM iot_devices          -- replace with your actual table path
),
iot_measurements AS (
    SELECT * FROM iot_measurements     -- replace with your actual table path
),
iot_device_errors AS (
    SELECT * FROM iot_device_errors    -- replace with your actual table path
)
-- Your analysis below
--------------------------------------------------------------------------------
```

Submit your work as a `.sql` file. Add comments inside the file to explain your reasoning where the code alone is not self-explanatory.

---

## Part 1 – Questions

### Question 1 – Understand the data

Before modelling behavior, characterize what you have.

a. **Time coverage**
   - Earliest and latest `timestamp` in the telemetry file.
   - Earliest and latest `start_time` in the errors file.
   - If these ranges differ, say what that implies for joining errors to telemetry.

b. **Scale**
   - Count of distinct `device_id` in each file.
   - Count of devices that appear in telemetry but not in the system-attributes file, and the reverse (if any).

c. **System mix**
   - Distribution of devices by `firmware`, `network_type`, and `region` (tables or counts).

d. **Errors**
   - How many distinct `error_code` values?
   - Frequency of the most common codes.
   - How many distinct devices have **at least one** error row?
   - How many devices appear in telemetry but have **no** error rows in the extract?

e. **Telemetry frequency**
   - Infer the typical interval between consecutive readings for a system (e.g. median gap when the system is “present”).
   - Note any devices or periods that clearly violate that pattern (without yet defining “affected”).

---

### Question 2 – Identify devices with Connectivity Problems

The scenario mentions **intermittent** behavior — not necessarily one long blackout, but repeated periods without expected data.

You do **not** receive a separate connect/disconnect log. **Derive offline or “gap” periods from the telemetry timestamps** for each `device_id` (e.g. using differences between consecutive `timestamp` values ordered per system).

**Define and apply two rules** (use the same definitions for all devices):

| Rule | Suggested definition (you may refine it, but justify changes) |
|------|----------------------------------------------------------------|
| **Long gap** | At least one interval between consecutive readings **≥ 2 days** (2,880 minutes) longer than the nominal reporting interval you inferred in Q1e. |
| **Short recurring gaps** | At least **3** separate gaps **≥ 1 hour** (beyond the nominal interval) within any rolling **7-day** window. |

For each rule:

a. How many **distinct devices** satisfy it?
b. List the **top 20 devices** by **total gap minutes** in the **last 30 days** of the telemetry range (define “gap minutes” consistently). Include at least: `device_id`, count of gap events (or distinct gap periods), total gap minutes, maximum single gap (minutes).

c. **Consistency check:** For those top devices, summarize error activity in the same period (e.g. error count per system, or presence/absence). Briefly state whether error timing and telemetry gaps line up in a way you find plausible.

---

### Question 3 – Isolate and Profile the Affected devices

Take the set of devices you flagged in Question 2 (or a clearly defined subset, e.g. top 20 by gap minutes). Profile them relative to the rest of the fleet.

a. Compare **installation timing**: e.g. share of flagged devices by installation month or year vs. the full fleet (using `installation_date`).

b. **Errors:** For flagged vs. non-flagged devices, compare error rates (e.g. errors per system per week, or per calendar week) and the most frequent `error_code` values in each group.

c. **Extended silence:** Identify devices that show **no telemetry** for a continuous window **longer than 24 hours** (according to your gap definition). How many devices? What is the longest such window per system? Optionally relate timing to error rows if helpful.

d. **Trend:** For the **10 devices** with the largest total gap minutes (in the full telemetry range or in the last 90 days — state which), describe how **weekly** total gap minutes evolve over time. Is behavior stable, worsening, or improving?

> **Deliverable:** A short prioritization narrative: which devices worry you most and what evidence supports that.

---

### Question 4 – Segmentation

Test whether problems cluster by attributes in the system file.

a. **Firmware:** Among devices you flagged in Q2, is activity concentrated in certain `firmware` values compared to the fleet baseline? Quantify (e.g. share of gap minutes, share of flagged devices).

b. **Network:** Same question for `network_type`.

c. **Region:** Same question for `region`.

d. **Installation cohort:** Same question by installation period (month or quarter — your choice, but be consistent).

e. **Strongest pattern:** In one paragraph plus supporting numbers, describe the **single segmentation** that best separates “high concern” from “typical” in your view. Explain how you measured “best” (e.g. lift, concentration of gap minutes, simple rate difference).
   > Do **not** assume there must be one magic combination; if the data does not support a sharp split, say so and show what you tried.

---

### Question 5 – Escalation list

There is still no ticket table. Build a **prioritized list** of devices you would ask operations to review first.

a. **Rules:** Before final numbers, write down explicit rules for at least two priority levels (e.g. high vs. medium). Your rules may use telemetry gaps, error codes, and system attributes. Explain what you treat as noise vs. signal.

b. **Apply the rules:** How many devices fall into each level? What fraction of all devices is that?

c. **Output:** Table or list of the **top 20** devices you escalate first, with columns you believe are essential (e.g. `device_id`, priority, brief reason, key metrics).

d. **Edge case:** How do you treat devices with **long telemetry absence** but **no** error rows in the errors file in the same period? Where do they land in your priority scheme, and why?

e. **Timing:** Is there a week or date range where **many** devices first show unusual gaps or errors? Describe the evidence; you do not need a definitive external cause.

> **Part 2:** Be ready to present your Q4–Q5 logic and discuss trade-offs (false positives vs. missed cases).

---

### Question 6 – Written reflection (no code required)

a. What **additional data** (not in these files) would most improve root-cause confidence? List a few concrete examples.

b. State **at least two** plausible hypotheses for what might drive intermittent behavior in the field. For each: what in **your** analysis supports or weakens it, and what data would falsify it?

c. If your Q5 rules were turned into production alerts, what could go wrong, and how would you iterate with stakeholders?

d. What **limitations** of these extracts should a non-technical audience hear before acting on your numbers?

---

## Deliverables

| Item | Format |
|------|--------|
| SQL queries (Q1–Q5) | `.sql` file with inline comments |
| Written answers (Q6 + short comments per question) | Markdown, Word, or PDF |
| Optional charts | Screenshots attached to your submission |
| Escalation list (Q5c) | CSV or spreadsheet for Part 2 |

---

## Evaluation criteria

| Dimension | What we look for |
|-----------|------------------|
| Data understanding | Sensible profiling, awareness of coverage and joins |
| Technical quality | Correct logic for gaps, windows, and aggregates |
| Problem framing | Clear definitions; justified thresholds |
| Insight | Links telemetry, errors, and attributes; honest if patterns are weak |
| Communication | Readable for someone who did not run your code |
| Prioritization | Defensible escalation rules and awareness of edge cases |

---

## Notes

- There is **not** one official numeric answer; consistent reasoning matters.
- If you change our suggested gap thresholds, explain why.
- **Time guide:** roughly 3–5 hours for Part 1; depth over perfection.

---
