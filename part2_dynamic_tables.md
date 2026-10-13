# Part 2: Building a Data Transformation Pipeline with Dynamic Tables

## Overview

In this part, you will transform raw data synced by the ServiceNow Connector into an analysis-friendly format using Dynamic Tables. Dynamic Tables are declarative data pipelines that automatically refresh when source data is updated.

## Prerequisites

- Part 1 is completed, and the following tables are synced:
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT`
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER`
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP`
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA`

> **Note**: Tables synced by the Connector are stored in VARIANT format (the `RAW` column). We use the `RAW:field::TYPE` syntax in Dynamic Tables to flatten the data.

---

## Step 1: Create the Hands-on Database and Schema

```sql
-- =============================================
-- Step 1: Create analytics database and schema
-- =============================================
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS SERVICENOW_HANDSON;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS;
```

> **Explanation**: By separating the synced data (`SERVICENOW_DEST_DB`) from the analytics tables (`SERVICENOW_HANDSON`), we keep the roles clearly defined.

---

## Step 2: Dynamic Table 1 — Incident Detail Table

Join incident data with user and group data, and calculate MTTR (Mean Time to Repair) and SLA compliance.

```sql
-- =============================================
-- Step 2: DT_INCIDENT_ENRICHED
-- Incident x User x Group join, MTTR & SLA calculation
-- =============================================
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

CREATE OR REPLACE DYNAMIC TABLE DT_INCIDENT_ENRICHED
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    i.RAW:number::STRING                               AS incident_number,
    i.RAW:short_description::STRING                    AS short_description,
    i.RAW:description::STRING                          AS description,
    i.RAW:category::STRING                             AS category,
    i.RAW:subcategory::STRING                          AS subcategory,
    i.RAW:priority::STRING                             AS priority,
    i.RAW:urgency::STRING                              AS urgency,
    i.RAW:impact::STRING                               AS impact,
    i.RAW:state::STRING                                AS state,
    -- Priority label mapping
    CASE i.RAW:priority::STRING
        WHEN '1' THEN '1 - Critical'
        WHEN '2' THEN '2 - High'
        WHEN '3' THEN '3 - Moderate'
        WHEN '4' THEN '4 - Low'
        WHEN '5' THEN '5 - Planning'
        ELSE i.RAW:priority::STRING
    END                                                AS priority_label,
    -- State label mapping
    CASE i.RAW:state::STRING
        WHEN '1' THEN 'New'
        WHEN '2' THEN 'In Progress'
        WHEN '3' THEN 'On Hold'
        WHEN '6' THEN 'Resolved'
        WHEN '7' THEN 'Closed'
        WHEN '8' THEN 'Canceled'
        ELSE i.RAW:state::STRING
    END                                                AS state_label,
    -- Group information (joined with sys_user_group)
    i.RAW:assignment_group:value::STRING               AS assignment_group_id,
    g.RAW:name::STRING                                 AS assignment_group_name,
    -- Assignee information (joined with sys_user)
    i.RAW:assigned_to:value::STRING                    AS assigned_to_id,
    u.RAW:name::STRING                                 AS assigned_to_name,
    u.RAW:email::STRING                                AS assigned_to_email,
    -- Timestamps (safely convert empty strings to timestamps)
    TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING)     AS opened_at,
    TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)   AS resolved_at,
    TRY_TO_TIMESTAMP_NTZ(i.RAW:closed_at::STRING)     AS closed_at,
    -- MTTR (time to resolution) calculated in hours
    CASE
        WHEN NULLIF(i.RAW:resolved_at::STRING, '') IS NOT NULL
         AND NULLIF(i.RAW:opened_at::STRING, '') IS NOT NULL
        THEN ROUND(DATEDIFF('minute',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) / 60.0, 2)
        ELSE NULL
    END                                                AS mttr_hours,
    -- SLA compliance check (P1=4h, P2=8h, P3=24h, P4=72h)
    CASE
        WHEN NULLIF(i.RAW:resolved_at::STRING, '') IS NULL THEN NULL
        WHEN i.RAW:priority::STRING = '1' AND DATEDIFF('hour',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) <= 4 THEN TRUE
        WHEN i.RAW:priority::STRING = '2' AND DATEDIFF('hour',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) <= 8 THEN TRUE
        WHEN i.RAW:priority::STRING = '3' AND DATEDIFF('hour',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) <= 24 THEN TRUE
        WHEN i.RAW:priority::STRING = '4' AND DATEDIFF('hour',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) <= 72 THEN TRUE
        ELSE FALSE
    END                                                AS sla_met,
    i.SYS_ID                                           AS sys_id
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT i
LEFT JOIN SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER u
    ON i.RAW:assigned_to:value::STRING = u.SYS_ID AND u.IS_DELETED = FALSE
LEFT JOIN SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP g
    ON i.RAW:assignment_group:value::STRING = g.SYS_ID AND g.IS_DELETED = FALSE
WHERE i.IS_DELETED = FALSE;
```

> **Explanation**:
> - Data synced by the Connector is stored in the `RAW` column (VARIANT type). Use `RAW:field::TYPE` to flatten it
> - Reference fields (`assigned_to`, `assignment_group`) have an object structure like `{value: "sys_id", link: "..."}`. Extract the sys_id with `RAW:assigned_to:value::STRING` and join with the `SYS_USER` / `SYS_USER_GROUP` tables
> - Empty strings cause errors during timestamp conversion, so `TRY_TO_TIMESTAMP_NTZ` and `NULLIF` are used
> - **MTTR**: Calculated as the difference from `OPENED_AT` to `RESOLVED_AT` in hours
> - **SLA Compliance Check**: Resolution time thresholds are set per priority (P1: 4h, P2: 8h, P3: 24h, P4: 72h)
> - `TARGET_LAG = '1 hour'`: Refreshes within a maximum of 1 hour after source data is updated

---

## Step 3: Dynamic Table 2 — Daily Incident Statistics

```sql
-- =============================================
-- Step 3: DT_INCIDENT_DAILY_STATS
-- Daily incident aggregation
-- =============================================
CREATE OR REPLACE DYNAMIC TABLE DT_INCIDENT_DAILY_STATS
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    DATE_TRUNC('day', opened_at)::DATE                AS report_date,
    DAYNAME(opened_at)                                AS day_of_week,
    COUNT(*)                                          AS total_incidents,
    COUNT(CASE WHEN state_label IN ('Resolved', 'Closed') THEN 1 END)
                                                      AS resolved_incidents,
    COUNT(CASE WHEN state_label IN ('New', 'In Progress', 'On Hold') THEN 1 END)
                                                      AS open_incidents,
    ROUND(AVG(mttr_hours), 2)                         AS avg_mttr_hours,
    ROUND(
        COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0),
        2
    )                                                 AS sla_compliance_pct,
    MODE(category)                                    AS top_category
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
WHERE opened_at IS NOT NULL
GROUP BY DATE_TRUNC('day', opened_at)::DATE, DAYNAME(opened_at);
```

> **Explanation**:
> - Aggregates daily incident counts, resolved counts, and open counts
> - `sla_compliance_pct`: SLA compliance rate (%)
> - `top_category`: The most frequent category for that day
> - This table references `DT_INCIDENT_ENRICHED`, so it chains together as a pipeline

---

## Step 4: Dynamic Table 3 — SLA Analysis Table

```sql
-- =============================================
-- Step 4: DT_SLA_ANALYSIS
-- Analyze SLA achievement status from the task_sla table
-- =============================================
CREATE OR REPLACE DYNAMIC TABLE DT_SLA_ANALYSIS
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    s.SYS_ID                                           AS sla_record_id,
    s.RAW:task:value::STRING                           AS task_id,
    i.RAW:number::STRING                               AS incident_number,
    i.RAW:short_description::STRING                    AS incident_description,
    i.RAW:priority::STRING                             AS priority,
    s.RAW:stage::STRING                                AS stage,
    s.RAW:has_breached::BOOLEAN                        AS has_breached,
    s.RAW:percentage::FLOAT                            AS percentage,
    s.RAW:business_percentage::FLOAT                   AS business_percentage,
    TRY_TO_TIMESTAMP_NTZ(s.RAW:start_time::STRING)    AS start_time,
    TRY_TO_TIMESTAMP_NTZ(s.RAW:end_time::STRING)      AS end_time,
    CASE
        WHEN NULLIF(s.RAW:end_time::STRING, '') IS NOT NULL
         AND NULLIF(s.RAW:start_time::STRING, '') IS NOT NULL
        THEN ROUND(DATEDIFF('minute',
               TRY_TO_TIMESTAMP_NTZ(s.RAW:start_time::STRING),
               TRY_TO_TIMESTAMP_NTZ(s.RAW:end_time::STRING)) / 60.0, 2)
        ELSE NULL
    END                                                AS duration_hours
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA s
LEFT JOIN SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT i
    ON s.RAW:task:value::STRING = i.SYS_ID AND i.IS_DELETED = FALSE
WHERE s.IS_DELETED = FALSE;
```

> **Explanation**:
> - Joins the `task_sla` table with the `incident` table to enrich SLA records with incident information
> - `stage`: The progress state of the SLA (`achieved`, `breached`, `in_progress`, `cancelled`, etc.)
> - `has_breached`: Whether the SLA was breached
> - `percentage`: SLA consumption rate (over 100% = breached)

---

## Step 5: Dynamic Table 4 — Team Performance

```sql
-- =============================================
-- Step 5: DT_TEAM_PERFORMANCE
-- Performance metrics by team (Assignment Group)
-- =============================================
CREATE OR REPLACE DYNAMIC TABLE DT_TEAM_PERFORMANCE
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    assignment_group_name                              AS assignment_group,
    COUNT(*)                                          AS total_incidents,
    COUNT(CASE WHEN state_label IN ('Resolved', 'Closed') THEN 1 END)
                                                      AS resolved_incidents,
    COUNT(CASE WHEN state_label IN ('New', 'In Progress', 'On Hold') THEN 1 END)
                                                      AS open_incidents,
    ROUND(AVG(mttr_hours), 2)                         AS avg_mttr_hours,
    COUNT(CASE WHEN priority IN ('1', '2') THEN 1 END) AS high_priority_count,
    ROUND(
        COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0),
        2
    )                                                 AS sla_compliance_pct,
    MODE(category)                                    AS top_category
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
WHERE assignment_group_name IS NOT NULL
  AND assignment_group_name != ''
GROUP BY assignment_group_name;
```

> **Explanation**:
> - Aggregates incident response results by team (Assignment Group)
> - `avg_mttr_hours`: Average resolution time per team
> - `sla_compliance_pct`: SLA compliance rate per team
> - `high_priority_count`: Count of high-priority (P1, P2) incidents

---

## Step 6: Verify the Dynamic Tables

### 6.1 Check the Dynamic Tables List

```sql
-- =============================================
-- Step 6.1: Check the list and status of Dynamic Tables
-- =============================================
SHOW DYNAMIC TABLES IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;
```

### 6.2 Execute Manual Refresh

```sql
-- =============================================
-- Step 6.2: Manual refresh
-- =============================================
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED REFRESH;
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS REFRESH;
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS REFRESH;
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE REFRESH;
```

> **Explanation**: You can execute an immediate refresh with `ALTER DYNAMIC TABLE ... REFRESH`. Normally, automatic refreshes occur based on the `TARGET_LAG`, but during the hands-on session we execute them manually to verify data promptly.

### 6.3 Verify the Data

```sql
-- =============================================
-- Step 6.3: Verify data in each table
-- =============================================

-- Incident details
SELECT incident_number, short_description, priority_label, state_label,
       assignment_group_name, assigned_to_name, mttr_hours, sla_met
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
LIMIT 10;

-- Daily statistics
SELECT report_date, total_incidents, resolved_incidents, avg_mttr_hours, sla_compliance_pct
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS
ORDER BY report_date DESC
LIMIT 10;

-- SLA analysis
SELECT incident_number, incident_description, stage, has_breached, percentage, duration_hours
FROM SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
LIMIT 10;

-- Team performance
SELECT assignment_group, total_incidents, avg_mttr_hours, sla_compliance_pct
FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
ORDER BY total_incidents DESC;
```

---

## Pipeline Structure

```
ServiceNow (Connector)
    │
    ├── INCIDENT (RAW) ──────────┐
    ├── SYS_USER (RAW) ──────────┤
    ├── SYS_USER_GROUP (RAW) ────┤
    │                            ▼
    │                DT_INCIDENT_ENRICHED
    │                   │          │
    │                   ▼          ▼
    │    DT_INCIDENT_DAILY_STATS   DT_TEAM_PERFORMANCE
    │
    ├── TASK_SLA (RAW) ──────────┐
    │                            │
    ├── INCIDENT (RAW) ──────────┤
    │                            ▼
    │                  DT_SLA_ANALYSIS
```

> **Key Point**: Dynamic Tables are declarative pipelines. You only need to define the logic with a SQL SELECT statement, and Snowflake handles automatic data updates and dependency management. By simply setting `TARGET_LAG`, there is no need to manage refresh schedules.

---

## Summary

What was accomplished in this part:

1. Created the analytics database and schema (`SERVICENOW_HANDSON.ANALYTICS`)
2. Created 4 Dynamic Tables:
   - `DT_INCIDENT_ENRICHED`: Incident details (user/group joins, MTTR, SLA compliance)
   - `DT_INCIDENT_DAILY_STATS`: Daily incident statistics
   - `DT_SLA_ANALYSIS`: SLA achievement analysis (using the task_sla table)
   - `DT_TEAM_PERFORMANCE`: Team performance
3. Performed manual refreshes and verified the data

**Next Part**: Proceed to [Part 3: Analysis and Visualization with Snowflake Notebooks](part3_analysis_notebook.md).
