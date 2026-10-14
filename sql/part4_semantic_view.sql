-- =============================================================================
-- Part 4: Semantic View + Cortex Analyst Setup (Enhanced)
-- =============================================================================
-- Create a Semantic View (metadata definition) on top of Dynamic Tables,
-- enabling an environment where SQL can be auto-generated and executed
-- from natural language.
-- The Semantic View serves as the backend for Cortex Analyst / Cortex Agent.
--
-- Enhancements over basic version:
--   - SYNONYMS on tables/dimensions/metrics for natural language flexibility
--   - SAMPLE_VALUES + IS_ENUM on categorical dimensions for accurate filtering
--   - (LABELS = (FILTER) removed: not yet supported in this account version)
--   - Richer COMMENTs with business context for AI-friendly descriptions
--   - AI_QUESTION_CATEGORIZATION for question routing
--   - 12 Verified Queries (VQR) including Japanese patterns
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW

  -- ===== Table definitions =====
  TABLES (
    incidents AS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
      PRIMARY KEY (sys_id)
      WITH SYNONYMS = ('tickets', 'incident tickets', 'service requests', 'issues')
      COMMENT = 'Enriched incident detail table joining ServiceNow INCIDENT, SYS_USER, and SYS_USER_GROUP. 1 row = 1 incident. Contains MTTR, SLA compliance, priority/state labels, and assignee details.',
    daily_stats AS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS
      PRIMARY KEY (report_date)
      WITH SYNONYMS = ('daily report', 'daily summary', 'daily metrics')
      COMMENT = 'Pre-aggregated daily incident statistics. 1 row = 1 day. Includes total/resolved counts, average MTTR, SLA compliance rate, and top category per day.',
    sla_analysis AS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
      PRIMARY KEY (sla_record_id)
      WITH SYNONYMS = ('SLA records', 'service level agreements', 'SLA tracking')
      COMMENT = 'SLA achievement analysis joining TASK_SLA with INCIDENT. 1 row = 1 SLA record. Tracks SLA stage (achieved/breached/in_progress), breach status, and percentage consumed.',
    team_performance AS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
      PRIMARY KEY (assignment_group)
      WITH SYNONYMS = ('team stats', 'group performance', 'team metrics')
      COMMENT = 'Team-level performance summary. 1 row = 1 assignment group. Aggregates total incidents, average MTTR, SLA compliance, high-priority count, and top category per team.',
    event_logs AS SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
      PRIMARY KEY (event_id)
      WITH SYNONYMS = ('server logs', 'infrastructure events', 'system events', 'IT events')
      COMMENT = 'IT infrastructure event logs (50 million rows). 1 row = 1 event. Covers server-level events with type (INFO/WARNING/ERROR/CRITICAL), category, source IP, and message.',
    event_correlation AS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
      PRIMARY KEY (event_date, category)
      WITH SYNONYMS = ('event incident correlation', 'correlation summary')
      COMMENT = 'Daily correlation between IT events and incidents by category. 1 row = 1 day x category combination. Links infrastructure event volume to incident patterns.'
  )

  -- ===== Relationships =====
  RELATIONSHIPS (
    incidents_to_daily AS
      incidents (opened_at) REFERENCES daily_stats (report_date)
  )

  -- ===== Dimensions =====
  DIMENSIONS (
    -- incidents table
    incidents.dim_incident_number AS incident_number
      WITH SYNONYMS = ('ticket number', 'INC number', 'incident ID')
      COMMENT = 'Unique incident identifier (e.g., INC0000001). Format: INC + 7-digit zero-padded number.',
    incidents.dim_short_description AS short_description
      WITH SYNONYMS = ('summary', 'title', 'incident description', 'issue description')
      COMMENT = 'Brief one-line summary of the incident as entered by the reporter or service desk agent.',
    incidents.dim_category AS category
      WITH SYNONYMS = ('incident type', 'issue category', 'problem area')
      COMMENT = 'Incident category classifying the type of IT issue.'
      SAMPLE_VALUES ('network', 'software', 'hardware', 'inquiry', 'database')
      IS_ENUM,
    incidents.dim_priority_label AS priority_label
      WITH SYNONYMS = ('priority', 'severity', 'urgency level')
      COMMENT = 'Human-readable priority label mapped from numeric codes. Determines SLA response targets.'
      SAMPLE_VALUES ('1 - Critical', '2 - High', '3 - Moderate', '4 - Low', '5 - Planning')
      IS_ENUM,
    incidents.dim_state_label AS state_label
      WITH SYNONYMS = ('status', 'incident status', 'current state')
      COMMENT = 'Current lifecycle state of the incident.'
      SAMPLE_VALUES ('New', 'In Progress', 'On Hold', 'Resolved', 'Closed', 'Canceled')
      IS_ENUM,
    incidents.dim_assignment_group AS assignment_group_name
      WITH SYNONYMS = ('team', 'support team', 'assigned team', 'group')
      COMMENT = 'Name of the assignment group (team) responsible for resolving the incident.',
    incidents.dim_assigned_to AS assigned_to_name
      WITH SYNONYMS = ('assignee', 'engineer', 'person assigned', 'handler')
      COMMENT = 'Full name of the individual assigned to work on the incident.',
    incidents.dim_opened_at AS opened_at
      WITH SYNONYMS = ('created date', 'open date', 'reported date')
      COMMENT = 'Timestamp when the incident was first opened/reported in ServiceNow.',
    incidents.dim_resolved_at AS resolved_at
      WITH SYNONYMS = ('resolution date', 'fixed date', 'closed date')
      COMMENT = 'Timestamp when the incident was resolved. NULL if still open.',
    incidents.dim_sla_met AS sla_met
      WITH SYNONYMS = ('SLA achieved', 'within SLA', 'SLA compliant')
      COMMENT = 'Whether the incident was resolved within the SLA target. TRUE = met, FALSE = breached, NULL = unresolved.',
    -- daily_stats table
    daily_stats.dim_report_date AS report_date
      WITH SYNONYMS = ('date', 'day')
      COMMENT = 'Calendar date for the daily statistics row.',
    daily_stats.dim_day_of_week AS day_of_week
      WITH SYNONYMS = ('weekday', 'day name')
      COMMENT = 'Day of the week name (e.g., Monday, Tuesday).'
      SAMPLE_VALUES ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
      IS_ENUM,
    daily_stats.dim_top_category AS top_category
      COMMENT = 'The most frequently occurring incident category on that day.',
    -- sla_analysis table
    sla_analysis.dim_incident_number AS incident_number
      WITH SYNONYMS = ('ticket number')
      COMMENT = 'Incident number linked to this SLA record (joined from INCIDENT table).',
    sla_analysis.dim_stage AS stage
      WITH SYNONYMS = ('SLA stage', 'SLA status', 'SLA outcome')
      COMMENT = 'Current SLA lifecycle stage.'
      SAMPLE_VALUES ('achieved', 'breached', 'in_progress', 'cancelled', 'paused')
      IS_ENUM,
    sla_analysis.dim_has_breached AS has_breached
      WITH SYNONYMS = ('SLA violated', 'SLA breached', 'exceeded deadline')
      COMMENT = 'TRUE if SLA deadline was ever exceeded, even if later achieved. FALSE means never breached.',
    -- team_performance table
    team_performance.dim_team_name AS assignment_group
      WITH SYNONYMS = ('team name', 'support group')
      COMMENT = 'Assignment group (team) name.',
    team_performance.dim_top_category AS top_category
      COMMENT = 'The category most frequently handled by this team.',
    -- event_logs table
    event_logs.dim_server_name AS server_name
      WITH SYNONYMS = ('host', 'hostname', 'machine name', 'server')
      COMMENT = 'Server hostname generating the event (e.g., app-server-01, db-server-03).',
    event_logs.dim_event_type AS event_type
      WITH SYNONYMS = ('log level', 'severity', 'event severity')
      COMMENT = 'Severity level of the IT event.'
      SAMPLE_VALUES ('INFO', 'WARNING', 'ERROR', 'CRITICAL')
      IS_ENUM,
    event_logs.dim_category AS category
      WITH SYNONYMS = ('event category')
      COMMENT = 'Infrastructure event category, aligned with incident categories for correlation.'
      SAMPLE_VALUES ('network', 'software', 'hardware', 'inquiry', 'database')
      IS_ENUM,
    event_logs.dim_timestamp AS timestamp
      WITH SYNONYMS = ('event time', 'log time', 'occurred at')
      COMMENT = 'Exact timestamp when the infrastructure event occurred.',
    event_logs.dim_source_ip AS source_ip
      WITH SYNONYMS = ('IP address', 'origin IP', 'source address')
      COMMENT = 'IP address of the system that generated the event.',
    -- event_correlation table
    event_correlation.dim_event_date AS event_date
      COMMENT = 'Date for the event-incident correlation row.',
    event_correlation.dim_category AS category
      COMMENT = 'Category used to correlate events and incidents (same taxonomy).'
  )

  -- ===== Metrics =====
  METRICS (
    -- incidents table
    incidents.avg_mttr AS AVG(mttr_hours)
      WITH SYNONYMS = ('average resolution time', 'mean time to resolve', 'avg MTTR', 'resolution speed')
      COMMENT = 'Mean Time To Resolve in hours. Calculated as DATEDIFF(hour, opened_at, resolved_at). Lower is better. NULL incidents are excluded.',
    incidents.incident_count AS COUNT(*)
      WITH SYNONYMS = ('number of incidents', 'ticket count', 'total tickets', 'how many incidents')
      COMMENT = 'Total count of incidents matching the filter criteria.',
    incidents.resolved_count AS COUNT_IF(state_label = 'Resolved' OR state_label = 'Closed')
      WITH SYNONYMS = ('resolved incidents', 'fixed count', 'completed tickets')
      COMMENT = 'Count of incidents in Resolved or Closed state.',
    incidents.open_count AS COUNT_IF(state_label IN ('New', 'In Progress', 'On Hold'))
      WITH SYNONYMS = ('open incidents', 'unresolved tickets', 'active incidents', 'backlog')
      COMMENT = 'Count of incidents still open (New, In Progress, or On Hold).',
    incidents.sla_compliance_rate AS ROUND(COUNT_IF(sla_met = TRUE) * 100.0 / NULLIF(COUNT_IF(sla_met IS NOT NULL), 0), 2)
      WITH SYNONYMS = ('SLA rate', 'SLA achievement rate', 'SLA %')
      COMMENT = 'Percentage of incidents resolved within SLA target. Calculated only for incidents with a determined SLA status.',
    incidents.high_priority_count AS COUNT_IF(priority_label IN ('1 - Critical', '2 - High'))
      WITH SYNONYMS = ('critical and high count', 'urgent incidents', 'P1 P2 count')
      COMMENT = 'Count of Critical (P1) and High (P2) priority incidents.',
    -- daily_stats table
    daily_stats.ds_total_incidents AS SUM(total_incidents)
      WITH SYNONYMS = ('daily total', 'incidents per day')
      COMMENT = 'Sum of total incidents across the selected date range.',
    daily_stats.ds_resolved_incidents AS SUM(resolved_incidents)
      WITH SYNONYMS = ('daily resolved')
      COMMENT = 'Sum of resolved incidents across the selected date range.',
    daily_stats.ds_avg_mttr AS AVG(avg_mttr_hours)
      WITH SYNONYMS = ('daily average MTTR', 'daily resolution time')
      COMMENT = 'Average of daily MTTR values (hours) across the selected date range.',
    daily_stats.ds_sla_compliance AS AVG(sla_compliance_pct)
      WITH SYNONYMS = ('daily SLA rate')
      COMMENT = 'Average of daily SLA compliance percentages across the selected date range.',
    -- sla_analysis table
    sla_analysis.sla_record_count AS COUNT(*)
      WITH SYNONYMS = ('SLA count', 'number of SLA records')
      COMMENT = 'Total count of SLA tracking records.',
    sla_analysis.sla_avg_percentage AS AVG(percentage)
      WITH SYNONYMS = ('average SLA consumption', 'SLA usage rate')
      COMMENT = 'Average SLA time consumed as a percentage. Values > 100 indicate the SLA deadline was exceeded.',
    sla_analysis.breach_count AS COUNT_IF(has_breached = TRUE)
      WITH SYNONYMS = ('SLA violations', 'breached SLAs', 'SLA failures')
      COMMENT = 'Count of SLA records where the deadline was breached at some point.',
    -- team_performance table
    team_performance.team_total_incidents AS SUM(total_incidents)
      WITH SYNONYMS = ('team incident count', 'incidents per team')
      COMMENT = 'Total incidents handled by the team.',
    team_performance.team_avg_mttr AS AVG(avg_mttr_hours)
      WITH SYNONYMS = ('team resolution time', 'team MTTR')
      COMMENT = 'Average MTTR for the team (hours). Lower means faster resolution.',
    team_performance.team_sla_compliance AS AVG(sla_compliance_pct)
      WITH SYNONYMS = ('team SLA rate', 'team SLA %')
      COMMENT = 'Average SLA compliance rate for the team (%). Higher is better.',
    -- event_logs table
    event_logs.event_log_count AS COUNT(*)
      WITH SYNONYMS = ('total events', 'event count', 'log count')
      COMMENT = 'Total count of IT infrastructure event log entries.',
    event_logs.critical_event_count AS COUNT_IF(event_type = 'CRITICAL')
      WITH SYNONYMS = ('critical count', 'critical events')
      COMMENT = 'Count of CRITICAL severity events. These indicate major outages or failures.',
    event_logs.error_event_count AS COUNT_IF(event_type = 'ERROR')
      WITH SYNONYMS = ('error count', 'errors')
      COMMENT = 'Count of ERROR severity events. These indicate service degradation.',
    event_logs.warning_event_count AS COUNT_IF(event_type = 'WARNING')
      WITH SYNONYMS = ('warning count', 'warnings')
      COMMENT = 'Count of WARNING severity events. These are early indicators of potential issues.',
    -- event_correlation table
    event_correlation.total_events AS SUM(event_count)
      COMMENT = 'Total infrastructure events in the correlation summary.',
    event_correlation.total_critical_events AS SUM(critical_event_count)
      COMMENT = 'Total CRITICAL events in the correlation summary.',
    event_correlation.total_incidents AS SUM(incident_count)
      COMMENT = 'Total incidents in the correlation summary.',
    event_correlation.corr_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'Average MTTR from the correlation summary (hours).'
  )

  COMMENT = 'Semantic View for ServiceNow IT Service Management (ITSM) data and IT infrastructure event logs. Covers incident management, SLA tracking, team performance, and event-incident correlation analysis.'

  -- ===== Cortex Analyst custom instructions =====
  AI_SQL_GENERATION 'When a question is asked in Japanese, use Japanese column aliases. Round all numeric values to 2 decimal places. When asked about trends, order by date ascending. When comparing teams, order by the relevant metric descending. For percentage calculations, multiply by 100 and round to 2 decimal places. In VQR SQL, use column names with the dim_ prefix and use ASCII characters only for aliases.'

  AI_QUESTION_CATEGORIZATION 'Questions about incident trends, SLA compliance, team performance, MTTR analysis, and event correlation are all supported. If a question asks about individual employee performance reviews or HR data, respond that this data covers IT operations metrics only, not HR data. If a question is ambiguous about which time period, ask the user to specify the date range.'

  -- ===== Verified Queries (VQR) =====
  AI_VERIFIED_QUERIES (
    -- English VQRs
    category_mttr AS (
      QUESTION 'What is the average MTTR by category?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT dim_category AS category, ROUND(AVG(mttr_hours), 2) AS avg_mttr_hours, COUNT(*) AS incident_count FROM __incidents WHERE mttr_hours IS NOT NULL AND dim_category IS NOT NULL AND dim_category != '''' GROUP BY dim_category ORDER BY avg_mttr_hours DESC'
    ),
    top_team AS (
      QUESTION 'Which team handles the most incidents?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT dim_team_name AS team, total_incidents, ROUND(avg_mttr_hours, 2) AS avg_mttr_hours, ROUND(sla_compliance_pct, 2) AS sla_compliance_pct FROM __team_performance ORDER BY total_incidents DESC LIMIT 10'
    ),
    sla_breach AS (
      QUESTION 'How many SLA breaches are there by stage?'
      SQL 'SELECT dim_stage AS stage, COUNT(*) AS record_count, COUNT(CASE WHEN dim_has_breached = TRUE THEN 1 END) AS breached_count, ROUND(COUNT(CASE WHEN dim_has_breached = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS breach_rate_pct FROM __sla_analysis GROUP BY dim_stage ORDER BY record_count DESC'
    ),
    priority_distribution AS (
      QUESTION 'What is the incident distribution by priority?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT dim_priority_label AS priority, COUNT(*) AS incident_count, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage FROM __incidents GROUP BY dim_priority_label ORDER BY dim_priority_label'
    ),
    open_incidents AS (
      QUESTION 'How many incidents are currently open?'
      SQL 'SELECT dim_state_label AS status, COUNT(*) AS incident_count FROM __incidents WHERE dim_state_label IN (''New'', ''In Progress'', ''On Hold'') GROUP BY dim_state_label ORDER BY incident_count DESC'
    ),
    event_log_summary AS (
      QUESTION 'What is the event log severity breakdown?'
      SQL 'SELECT dim_event_type AS severity, COUNT(*) AS event_count, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage FROM __event_logs GROUP BY dim_event_type ORDER BY CASE dim_event_type WHEN ''CRITICAL'' THEN 1 WHEN ''ERROR'' THEN 2 WHEN ''WARNING'' THEN 3 WHEN ''INFO'' THEN 4 END'
    ),
    event_category_correlation AS (
      QUESTION 'How do event volumes correlate with incidents by category?'
      SQL 'SELECT dim_category AS category, SUM(event_count) AS total_events, SUM(critical_event_count) AS critical_events, SUM(incident_count) AS incidents, ROUND(AVG(avg_mttr_hours), 2) AS avg_mttr_hours FROM __event_correlation GROUP BY dim_category ORDER BY total_events DESC'
    ),
    team_sla_ranking AS (
      QUESTION 'Which teams have the best SLA compliance?'
      SQL 'SELECT dim_team_name AS team, ROUND(sla_compliance_pct, 2) AS sla_compliance_pct, total_incidents, ROUND(avg_mttr_hours, 2) AS avg_mttr_hours FROM __team_performance ORDER BY sla_compliance_pct DESC'
    ),
    -- Japanese VQRs
    jp_category_mttr AS (
      QUESTION 'カテゴリ別の平均解決時間は？'
      SQL 'SELECT dim_category AS category, ROUND(AVG(mttr_hours), 2) AS avg_mttr_hours, COUNT(*) AS incident_count FROM __incidents WHERE mttr_hours IS NOT NULL AND dim_category IS NOT NULL AND dim_category != '''' GROUP BY dim_category ORDER BY avg_mttr_hours DESC'
    ),
    jp_priority_summary AS (
      QUESTION '優先度別のインシデント数とSLA達成率は？'
      SQL 'SELECT dim_priority_label AS priority, COUNT(*) AS total, COUNT(CASE WHEN sla_met = TRUE THEN 1 END) AS sla_met_count, ROUND(COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0), 2) AS sla_compliance_pct FROM __incidents GROUP BY dim_priority_label ORDER BY dim_priority_label'
    ),
    jp_team_ranking AS (
      QUESTION 'チーム別のパフォーマンスランキングは？'
      SQL 'SELECT dim_team_name AS team, total_incidents, ROUND(avg_mttr_hours, 2) AS avg_mttr_hours, ROUND(sla_compliance_pct, 2) AS sla_compliance_pct, high_priority_count FROM __team_performance ORDER BY sla_compliance_pct DESC'
    ),
    jp_open_incidents AS (
      QUESTION '未解決のインシデントは何件ありますか？'
      SQL 'SELECT dim_state_label AS status, COUNT(*) AS incident_count FROM __incidents WHERE dim_state_label IN (''New'', ''In Progress'', ''On Hold'') GROUP BY dim_state_label ORDER BY incident_count DESC'
    )
  );

-- -----------------------------------------------------------------------------
-- Verification
-- -----------------------------------------------------------------------------
SHOW SEMANTIC VIEWS IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;
DESCRIBE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;
