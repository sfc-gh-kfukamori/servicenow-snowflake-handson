-- =============================================================================
-- Part 4: Semantic View + Cortex Analyst Setup
-- =============================================================================
-- Create a Semantic View (metadata definition) on top of Dynamic Tables,
-- enabling an environment where SQL can be auto-generated and executed
-- from natural language.
-- The Semantic View serves as the backend for Cortex Analyst / Cortex Agent.
--
-- Table definitions:
--   INCIDENTS         : Incident details (DT_INCIDENT_ENRICHED)
--   DAILY_STATS       : Daily statistics (DT_INCIDENT_DAILY_STATS)
--   SLA_ANALYSIS      : SLA analysis (DT_SLA_ANALYSIS)
--   TEAM_PERFORMANCE  : Team-level metrics (DT_TEAM_PERFORMANCE)
--   EVENT_LOGS        : IT event logs (IT_EVENT_LOGS, 50 million rows)
--   EVENT_CORRELATION : Event x incident correlation (DT_EVENT_INCIDENT_CORRELATION)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW

  -- ===== Table definitions (PRIMARY KEY specifies the table granularity) =====
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
      COMMENT = 'IT infrastructure event logs (1 row = 1 event, 50 million rows)',
    event_correlation AS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
      PRIMARY KEY (event_date, category)
      COMMENT = 'Event x incident correlation summary (by day and category)'
  )

  -- ===== Relationships (define join conditions between tables) =====
  RELATIONSHIPS (
    incidents_to_daily AS
      incidents (opened_at) REFERENCES daily_stats (report_date)
  )

  -- ===== Dimensions (analysis axes: category, date, team, etc.) =====
  DIMENSIONS (
    -- incidents table
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
      COMMENT = 'Assignment group name',
    incidents.dim_assigned_to AS assigned_to_name
      COMMENT = 'Assigned person name',
    incidents.dim_opened_at AS opened_at
      COMMENT = 'Date and time the incident was opened',
    incidents.dim_resolved_at AS resolved_at
      COMMENT = 'Date and time the incident was resolved',
    -- daily_stats table
    daily_stats.dim_report_date AS report_date
      COMMENT = 'Report date',
    daily_stats.dim_day_of_week AS day_of_week
      COMMENT = 'Day of the week',
    daily_stats.dim_top_category AS top_category
      COMMENT = 'Most frequent incident category for that day',
    -- sla_analysis table
    sla_analysis.dim_incident_number AS incident_number
      COMMENT = 'Incident number associated with the SLA',
    sla_analysis.dim_stage AS stage
      COMMENT = 'SLA progress stage (achieved, breached, in_progress, cancelled, paused)',
    sla_analysis.dim_has_breached AS has_breached
      COMMENT = 'SLA violation flag',
    -- team_performance table
    team_performance.dim_team_name AS assignment_group
      COMMENT = 'Assignment group name',
    team_performance.dim_top_category AS top_category
      COMMENT = 'Most frequently handled category by the team',
    -- event_logs table (50 million event logs)
    event_logs.dim_server_name AS server_name
      COMMENT = 'Server name (e.g., app-server-01)',
    event_logs.dim_event_type AS event_type
      COMMENT = 'Event type (INFO, WARNING, ERROR, CRITICAL)',
    event_logs.dim_category AS category
      COMMENT = 'Event category (network, software, hardware, inquiry, database)',
    event_logs.dim_timestamp AS timestamp
      COMMENT = 'Event occurrence timestamp',
    event_logs.dim_source_ip AS source_ip
      COMMENT = 'Source IP address of the event',
    -- event_correlation table (event x incident correlation)
    event_correlation.dim_event_date AS event_date
      COMMENT = 'Correlation date',
    event_correlation.dim_category AS category
      COMMENT = 'Correlation category'
  )

  -- ===== Metrics (aggregate measures: COUNT, SUM, AVG, etc.) =====
  METRICS (
    -- incidents table
    incidents.avg_mttr AS AVG(mttr_hours)
      COMMENT = 'Mean Time To Resolve (MTTR, in hours)',
    incidents.incident_count AS COUNT(*)
      COMMENT = 'Number of incidents',
    -- daily_stats table
    daily_stats.ds_total_incidents AS SUM(total_incidents)
      COMMENT = 'Total number of incidents',
    daily_stats.ds_resolved_incidents AS SUM(resolved_incidents)
      COMMENT = 'Number of resolved incidents',
    daily_stats.ds_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Daily average MTTR (hours)',
    daily_stats.ds_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = 'Daily SLA compliance rate (%)',
    -- sla_analysis table
    sla_analysis.sla_record_count AS COUNT(*)
      COMMENT = 'Number of SLA records',
    sla_analysis.sla_avg_percentage AS AVG(percentage)
      COMMENT = 'Average SLA consumption rate',
    -- team_performance table
    team_performance.team_total_incidents AS SUM(total_incidents)
      COMMENT = 'Total incidents per team',
    team_performance.team_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Team average MTTR (hours)',
    team_performance.team_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = 'Team SLA compliance rate (%)',
    -- event_logs table
    event_logs.event_log_count AS COUNT(*)
      COMMENT = 'Number of event log entries',
    event_logs.critical_event_count AS COUNT_IF(event_type = 'CRITICAL')
      COMMENT = 'Number of CRITICAL events',
    event_logs.error_event_count AS COUNT_IF(event_type = 'ERROR')
      COMMENT = 'Number of ERROR events',
    -- event_correlation table
    event_correlation.total_events AS SUM(event_count)
      COMMENT = 'Correlation summary: total events',
    event_correlation.total_critical_events AS SUM(critical_event_count)
      COMMENT = 'Correlation summary: CRITICAL events',
    event_correlation.total_incidents AS SUM(incident_count)
      COMMENT = 'Correlation summary: number of incidents',
    event_correlation.corr_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Correlation summary: average MTTR (hours)'
  )

  COMMENT = 'Semantic View for ServiceNow IT operations data + IT infrastructure event logs'

  -- ===== Cortex Analyst custom instructions =====
  AI_SQL_GENERATION 'When a question is asked in Japanese, use Japanese column aliases. Round numbers to 2 decimal places. In VQR SQL, use column names with the dim_ prefix and use ASCII characters only for aliases.'

  -- ===== Verified Queries (VQR): Used to improve Cortex Analyst accuracy =====
  AI_VERIFIED_QUERIES (
    category_mttr AS (
      QUESTION 'What is the MTTR by category?'
      SQL 'SELECT dim_category AS category, ROUND(AVG(mttr_hours), 2) AS avg_mttr, COUNT(*) AS incident_count FROM __incidents WHERE mttr_hours IS NOT NULL AND dim_category IS NOT NULL AND dim_category != '''' GROUP BY dim_category ORDER BY avg_mttr DESC'
    ),
    top_team AS (
      QUESTION 'Which team has the most incidents?'
      SQL 'SELECT dim_team_name AS team, total_incidents, avg_mttr_hours, sla_compliance_pct FROM __team_performance ORDER BY total_incidents DESC LIMIT 10'
    ),
    sla_breach AS (
      QUESTION 'How many SLA violations are there?'
      SQL 'SELECT dim_stage AS stage, COUNT(*) AS record_count, COUNT(CASE WHEN dim_has_breached = TRUE THEN 1 END) AS breached_count FROM __sla_analysis GROUP BY dim_stage ORDER BY record_count DESC'
    ),
    priority_sla AS (
      QUESTION 'What is the SLA compliance rate by priority?'
      SQL 'SELECT priority_label, COUNT(*) AS total, COUNT(CASE WHEN sla_met = TRUE THEN 1 END) AS sla_met_count, ROUND(COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0), 2) AS sla_compliance_pct FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED WHERE sla_met IS NOT NULL GROUP BY priority_label ORDER BY priority_label'
    ),
    event_log_summary AS (
      QUESTION 'What is the total number of event logs?'
      SQL 'SELECT COUNT(*) AS total_events, COUNT_IF(dim_event_type = ''CRITICAL'') AS critical_events, COUNT_IF(dim_event_type = ''ERROR'') AS error_events FROM __event_logs'
    ),
    event_category_summary AS (
      QUESTION 'What is the comparison of event count and incident count by category?'
      SQL 'SELECT dim_category AS category, SUM(event_count) AS total_events, SUM(critical_event_count) AS critical_events, SUM(incident_count) AS incidents, ROUND(AVG(avg_mttr_hours), 2) AS avg_mttr FROM __event_correlation GROUP BY dim_category ORDER BY total_events DESC'
    )
  );

-- -----------------------------------------------------------------------------
-- Verification
-- -----------------------------------------------------------------------------
SHOW SEMANTIC VIEWS IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;
DESCRIBE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;
