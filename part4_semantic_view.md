# Part 4: Semantic View + Cortex Analyst Setup

## Overview

In this part, we define a Semantic View on the Dynamic Tables created in Part 2 to build an environment where data can be queried using natural language. The Semantic View serves as the backend for Cortex Analyst and will also be used by the AI agent app in Part 5.

## Prerequisites

- Part 2 is complete and data exists in the following Dynamic Tables:
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE`
- Part 1.5 is complete and data exists in the following tables:
  - `SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS` (50 million event log rows)
  - `SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION` (event x incident correlation)

---

## Step 1: Semantic View Concepts

A Semantic View is an object that defines the following metadata on tables and views:

- **Tables**: Define the analysis target tables with logical names
- **Dimensions**: Analysis axes (category, date, team, etc.)
- **Metrics**: Aggregation measures (COUNT, SUM, AVG, etc.)
- **Relationships**: Join conditions between tables
- **VQR (Verified Queries)**: Pre-verified queries (used to improve Cortex Analyst accuracy)

This enables Cortex Analyst to accurately convert natural language questions into SQL.

---

## Step 2: Creating the Semantic View

Execute the following SQL to create the Semantic View.

```sql
-- =============================================
-- Step 2: Creating the Semantic View
-- =============================================
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW

  -- ===== Table Definitions (PRIMARY KEY to specify table granularity) =====
  TABLES (
    incidents AS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
      PRIMARY KEY (sys_id)
      COMMENT = 'Incident detail table (1 row = 1 incident)',
    daily_stats AS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS
      PRIMARY KEY (report_date)
      COMMENT = 'Daily incident statistics (1 row = 1 day)',
    sla_analysis AS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
      PRIMARY KEY (sla_record_id)
      COMMENT = 'SLA achievement analysis table (1 row = 1 SLA record)',
    team_performance AS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
      PRIMARY KEY (assignment_group)
      COMMENT = 'Team performance summary (1 row = 1 team)',
    event_logs AS SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
      PRIMARY KEY (event_id)
      COMMENT = 'IT infrastructure event logs (1 row = 1 event, 50 million records)',
    event_correlation AS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
      PRIMARY KEY (event_date, category)
      COMMENT = 'Event x incident correlation summary (daily by category)'
  )

  -- ===== Relationships =====
  RELATIONSHIPS (
    incidents_to_daily AS
      incidents (opened_at) REFERENCES daily_stats (report_date)
  )

  -- ===== Dimensions =====
  DIMENSIONS (
    -- incidents table dimensions
    incidents.dim_incident_number AS incident_number
      COMMENT = 'Incident number (e.g., INC0000001)',
    incidents.dim_short_description AS short_description
      COMMENT = 'Brief description of the incident',
    incidents.dim_category AS category
      COMMENT = 'Incident category (network, software, hardware, inquiry, database, etc.)',
    incidents.dim_priority_label AS priority_label
      COMMENT = 'Priority label (1 - Critical, 2 - High, 3 - Moderate, 4 - Low, 5 - Planning)',
    incidents.dim_state_label AS state_label
      COMMENT = 'Incident state (New, In Progress, On Hold, Resolved, Closed, Canceled)',
    incidents.dim_assignment_group AS assignment_group_name
      COMMENT = 'Assigned team name',
    incidents.dim_assigned_to AS assigned_to_name
      COMMENT = 'Assigned person name',
    incidents.dim_opened_at AS opened_at
      COMMENT = 'Date and time the incident was opened',
    incidents.dim_resolved_at AS resolved_at
      COMMENT = 'Date and time the incident was resolved',
    -- daily_stats table dimensions
    daily_stats.dim_report_date AS report_date
      COMMENT = 'Report date',
    daily_stats.dim_day_of_week AS day_of_week
      COMMENT = 'Day of the week',
    daily_stats.dim_top_category AS top_category
      COMMENT = 'Most frequent incident category for the day',
    -- sla_analysis table dimensions
    sla_analysis.dim_incident_number AS incident_number
      COMMENT = 'Incident number associated with the SLA',
    sla_analysis.dim_stage AS stage
      COMMENT = 'SLA progress stage (achieved, breached, in_progress, cancelled, paused)',
    sla_analysis.dim_has_breached AS has_breached
      COMMENT = 'SLA breach flag',
    -- team_performance table dimensions
    team_performance.dim_team_name AS assignment_group
      COMMENT = 'Assigned team name',
    team_performance.dim_top_category AS top_category
      COMMENT = 'Most frequently handled category by the team',
    -- event_logs table dimensions
    event_logs.dim_server_name AS server_name
      COMMENT = 'Server name (e.g., app-server-01)',
    event_logs.dim_event_type AS event_type
      COMMENT = 'Event type (INFO, WARNING, ERROR, CRITICAL)',
    event_logs.dim_category AS category
      COMMENT = 'Event category (network, software, hardware, inquiry, database)',
    event_logs.dim_timestamp AS timestamp
      COMMENT = 'Event occurrence date and time',
    event_logs.dim_source_ip AS source_ip
      COMMENT = 'Source IP address of the event',
    -- event_correlation table dimensions
    event_correlation.dim_event_date AS event_date
      COMMENT = 'Correlation date',
    event_correlation.dim_category AS category
      COMMENT = 'Correlation category'
  )

  -- ===== Metrics =====
  METRICS (
    -- incidents table metrics
    incidents.avg_mttr AS AVG(mttr_hours)
      COMMENT = 'Mean Time to Repair (MTTR, in hours)',
    incidents.incident_count AS COUNT(*)
      COMMENT = 'Incident count',
    -- daily_stats table metrics
    daily_stats.ds_total_incidents AS SUM(total_incidents)
      COMMENT = 'Total incident count',
    daily_stats.ds_resolved_incidents AS SUM(resolved_incidents)
      COMMENT = 'Resolved incident count',
    daily_stats.ds_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Daily average MTTR (hours)',
    daily_stats.ds_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = 'Daily SLA compliance rate (%)',
    -- sla_analysis table metrics
    sla_analysis.sla_record_count AS COUNT(*)
      COMMENT = 'SLA record count',
    sla_analysis.sla_avg_percentage AS AVG(percentage)
      COMMENT = 'Average SLA consumption rate',
    -- team_performance table metrics
    team_performance.team_total_incidents AS SUM(total_incidents)
      COMMENT = 'Team total incident count',
    team_performance.team_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Team average MTTR (hours)',
    team_performance.team_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = 'Team SLA compliance rate (%)',
    -- event_logs table metrics
    event_logs.event_log_count AS COUNT(*)
      COMMENT = 'Event log count',
    event_logs.critical_event_count AS COUNT_IF(event_type = 'CRITICAL')
      COMMENT = 'CRITICAL event count',
    event_logs.error_event_count AS COUNT_IF(event_type = 'ERROR')
      COMMENT = 'ERROR event count',
    -- event_correlation table metrics
    event_correlation.total_events AS SUM(event_count)
      COMMENT = 'Correlation aggregate: total event count',
    event_correlation.total_critical_events AS SUM(critical_event_count)
      COMMENT = 'Correlation aggregate: CRITICAL event count',
    event_correlation.total_incidents AS SUM(incident_count)
      COMMENT = 'Correlation aggregate: incident count',
    event_correlation.corr_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Correlation aggregate: average MTTR (hours)'
  )

  COMMENT = 'Semantic View for ServiceNow IT operations data + IT infrastructure event logs'

  -- ===== Cortex Analyst Custom Instructions =====
  AI_SQL_GENERATION 'When asked in Japanese, add Japanese aliases to columns. Round numbers to 2 decimal places.'

  -- ===== Verified Queries (VQR) =====
  AI_VERIFIED_QUERIES (
    category_mttr AS (
      QUESTION 'What is the MTTR by category?'
      SQL 'SELECT category,
                 ROUND(AVG(mttr_hours), 2) AS avg_mttr_hours,
                 COUNT(*) AS incident_count
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
          WHERE mttr_hours IS NOT NULL AND category IS NOT NULL AND category != ''''
          GROUP BY category
          ORDER BY avg_mttr_hours DESC'
    ),
    top_team AS (
      QUESTION 'Which team has the most incidents?'
      SQL 'SELECT assignment_group,
                 total_incidents,
                 avg_mttr_hours,
                 sla_compliance_pct
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
          ORDER BY total_incidents DESC
          LIMIT 10'
    ),
    sla_breach AS (
      QUESTION 'How many SLA breaches are there?'
      SQL 'SELECT stage,
            COUNT(*) AS record_count,
            COUNT(CASE WHEN has_breached = TRUE THEN 1 END) AS breached_count
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
          GROUP BY stage
          ORDER BY record_count DESC'
    ),
    priority_sla AS (
      QUESTION 'What is the SLA compliance rate by priority?'
      SQL 'SELECT priority_label,
                 COUNT(*) AS total,
                 COUNT(CASE WHEN sla_met = TRUE THEN 1 END) AS sla_met_count,
                 ROUND(COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0
                   / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0), 2) AS sla_compliance_pct
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
          WHERE sla_met IS NOT NULL
          GROUP BY priority_label
          ORDER BY priority_label'
    ),
    event_log_summary AS (
      QUESTION 'What is the total event log count?'
      SQL 'SELECT COUNT(*) AS total_events, COUNT_IF(dim_event_type = ''CRITICAL'') AS critical_events, COUNT_IF(dim_event_type = ''ERROR'') AS error_events FROM __event_logs'
    ),
    event_category_summary AS (
      QUESTION 'What is the comparison of event counts and incident counts by category?'
      SQL 'SELECT dim_category AS category, SUM(event_count) AS total_events, SUM(critical_event_count) AS critical_events, SUM(incident_count) AS incidents, ROUND(AVG(avg_mttr_hours), 2) AS avg_mttr FROM __event_correlation GROUP BY dim_category ORDER BY total_events DESC'
    )
  );
```

> **Notes**:
> - **DDL syntax**: `CREATE SEMANTIC VIEW` is defined in the order of `TABLES`, `RELATIONSHIPS`, `DIMENSIONS`, `METRICS`
> - Dimensions and metrics are defined in the format `<table_alias>.<semantic_name> AS <sql_expression>`
> - `AI_SQL_GENERATION`: Instructions for Cortex Analyst during SQL generation (Japanese aliases, etc.)
> - `AI_VERIFIED_QUERIES`: Define pairs of common questions and correct SQL to improve Cortex Analyst accuracy

---

## Step 3: Verifying the Semantic View

```sql
-- =============================================
-- Step 3: Verifying the Semantic View
-- =============================================

-- List Semantic Views
SHOW SEMANTIC VIEWS IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- Semantic View details
DESCRIBE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;
```

---

## Step 4: Testing Natural Language Queries with Cortex Analyst

### 4.1 How to Run in Snowsight

1. Log in to Snowsight
2. Select **AI & ML > Cortex Analyst** from the left menu
3. Select `SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW` as the Semantic View
4. Enter the following questions to test

### 4.2 Test Question Examples

#### Question 1: Category Analysis (VQR available)
```
Show the average MTTR by category
```

#### Question 2: Team Comparison (VQR available)
```
What are the top 5 teams with the most incidents?
```

#### Question 3: SLA Analysis (VQR available)
```
How many SLA breaches are there?
```

#### Question 4: SLA by Priority (VQR available)
```
Show the SLA compliance rate by priority
```

#### Question 5: Event Log Count (VQR available)
```
What is the total event log count?
```

#### Question 6: Event x Incident Correlation (VQR available)
```
What is the comparison of event counts and incident counts by category?
```

#### Question 7: Advanced (question not in VQR)
```
What is the most common incident category this month?
```

#### Question 8: Time Series Analysis
```
Show the monthly incident count trend for the last 6 months
```

> **Tip**: Questions defined in VQR (Verified Queries) are answered with high accuracy. Questions not in VQR will also have SQL generated based on dimension/metric definitions and comments, but if accuracy is low, you can add VQRs to improve it.

---

## Step 5: Calling Cortex Analyst from SQL (Optional)

Let's also review how to call Cortex Analyst programmatically.

```sql
-- =============================================
-- Step 5: Calling Cortex Analyst from SQL
-- =============================================

-- Convert a natural language query to SQL and execute
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'claude-3-5-sonnet',
  'Show the MTTR by category'
);
```

> **Note**: Cortex Analyst is typically used via the Snowsight UI or through a Cortex Agent. In Part 5, we will use the Semantic View through a Cortex Agent.

---

## Summary

What was accomplished in this part:

1. Understood Semantic View concepts (tables, dimensions, metrics, relationships, VQR)
2. Created a Semantic View with 6 tables:
   - `incidents`: Incident details
   - `daily_stats`: Daily statistics
   - `sla_analysis`: SLA analysis
   - `team_performance`: Team performance
   - `event_logs`: IT infrastructure event logs (50 million records)
   - `event_correlation`: Event x incident correlation summary
3. Configured 6 VQRs (Verified Queries) (incident analysis + event log analysis)
4. Tested natural language queries with Cortex Analyst

**Next Part**: Proceed to [Part 5: AI Agent App (App Runtime) Setup](part5_ai_agent_app.md).
