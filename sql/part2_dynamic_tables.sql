-- =============================================================================
-- Part 2: Building a Data Processing Pipeline with Dynamic Tables
-- =============================================================================
-- Transform raw data (VARIANT format) synced by the ServiceNow Connector
-- into flat, analysis-friendly tables using Dynamic Tables.
-- Dynamic Tables are declarative pipelines: just define the SQL and they
-- refresh automatically.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 1: Create the analytics database and schema
-- Separate synced data (SERVICENOW_DEST_DB) from analytics tables
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS SERVICENOW_HANDSON;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- -----------------------------------------------------------------------------
-- Step 2: DT_INCIDENT_ENRICHED (Incident detail table)
-- Join incident x user x group, and compute MTTR and SLA compliance.
-- Flatten the VARIANT column using RAW:field::TYPE syntax.
-- Reference fields (assigned_to, etc.) use {value: "sys_id"} format.
-- TARGET_LAG='1 hour': Refresh within 1 hour after source update.
-- -----------------------------------------------------------------------------
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
    -- Convert priority code to human-readable label
    CASE i.RAW:priority::STRING
        WHEN '1' THEN '1 - Critical'
        WHEN '2' THEN '2 - High'
        WHEN '3' THEN '3 - Moderate'
        WHEN '4' THEN '4 - Low'
        WHEN '5' THEN '5 - Planning'
        ELSE i.RAW:priority::STRING
    END                                                AS priority_label,
    -- Convert state code to label
    CASE i.RAW:state::STRING
        WHEN '1' THEN 'New'
        WHEN '2' THEN 'In Progress'
        WHEN '3' THEN 'On Hold'
        WHEN '6' THEN 'Resolved'
        WHEN '7' THEN 'Closed'
        WHEN '8' THEN 'Canceled'
        ELSE i.RAW:state::STRING
    END                                                AS state_label,
    -- Group info (joined with sys_user_group)
    i.RAW:assignment_group:value::STRING               AS assignment_group_id,
    g.RAW:name::STRING                                 AS assignment_group_name,
    -- Assignee info (joined with sys_user)
    i.RAW:assigned_to:value::STRING                    AS assigned_to_id,
    u.RAW:name::STRING                                 AS assigned_to_name,
    u.RAW:email::STRING                                AS assigned_to_email,
    -- Timestamps (safely convert empty strings to timestamps)
    TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING)     AS opened_at,
    TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)   AS resolved_at,
    TRY_TO_TIMESTAMP_NTZ(i.RAW:closed_at::STRING)     AS closed_at,
    -- MTTR (Mean Time To Resolve): time from open to resolution (in hours)
    CASE
        WHEN NULLIF(i.RAW:resolved_at::STRING, '') IS NOT NULL
         AND NULLIF(i.RAW:opened_at::STRING, '') IS NOT NULL
        THEN ROUND(DATEDIFF('minute',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) / 60.0, 2)
        ELSE NULL
    END                                                AS mttr_hours,
    -- SLA compliance check (target hours by priority: P1=4h, P2=8h, P3=24h, P4=72h)
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

-- -----------------------------------------------------------------------------
-- Step 3: DT_INCIDENT_DAILY_STATS (Daily incident statistics)
-- Aggregate DT_INCIDENT_ENRICHED to compute daily KPIs.
-- Chains to DT_INCIDENT_ENRICHED as a pipeline (auto-refresh).
-- -----------------------------------------------------------------------------
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
FROM DT_INCIDENT_ENRICHED
WHERE opened_at IS NOT NULL
GROUP BY DATE_TRUNC('day', opened_at)::DATE, DAYNAME(opened_at);

-- -----------------------------------------------------------------------------
-- Step 4: DT_SLA_ANALYSIS (SLA achievement analysis)
-- Join the task_sla table with incidents to visualize SLA achievement rates
-- and violations.
-- stage: achieved/breached/in_progress/cancelled
-- has_breached: SLA violation flag
-- percentage: SLA consumption rate (over 100% = violation)
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- Step 5: DT_TEAM_PERFORMANCE (Team-level performance)
-- Aggregate incident response metrics by assignment group.
-- avg_mttr_hours: average resolution time per team
-- sla_compliance_pct: SLA compliance rate per team
-- high_priority_count: number of high-priority (P1, P2) incidents
-- -----------------------------------------------------------------------------
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
FROM DT_INCIDENT_ENRICHED
WHERE assignment_group_name IS NOT NULL
  AND assignment_group_name != ''
GROUP BY assignment_group_name;

-- -----------------------------------------------------------------------------
-- Step 6: Manual refresh (execute during the hands-on to view data immediately)
-- Normally, auto-refresh occurs based on TARGET_LAG
-- -----------------------------------------------------------------------------
ALTER DYNAMIC TABLE DT_INCIDENT_ENRICHED REFRESH;
ALTER DYNAMIC TABLE DT_INCIDENT_DAILY_STATS REFRESH;
ALTER DYNAMIC TABLE DT_SLA_ANALYSIS REFRESH;
ALTER DYNAMIC TABLE DT_TEAM_PERFORMANCE REFRESH;

-- -----------------------------------------------------------------------------
-- Step 7: Verify data
-- -----------------------------------------------------------------------------

-- List and check status of Dynamic Tables
SHOW DYNAMIC TABLES IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- Incident details
SELECT incident_number, short_description, priority_label, state_label,
       assignment_group_name, assigned_to_name, mttr_hours, sla_met
FROM DT_INCIDENT_ENRICHED
LIMIT 10;

-- Daily statistics
SELECT report_date, total_incidents, resolved_incidents, avg_mttr_hours, sla_compliance_pct
FROM DT_INCIDENT_DAILY_STATS
ORDER BY report_date DESC
LIMIT 10;

-- SLA analysis
SELECT incident_number, incident_description, stage, has_breached, percentage, duration_hours
FROM DT_SLA_ANALYSIS
LIMIT 10;

-- Team-level performance
SELECT assignment_group, total_incidents, avg_mttr_hours, sla_compliance_pct
FROM DT_TEAM_PERFORMANCE
ORDER BY total_incidents DESC;
