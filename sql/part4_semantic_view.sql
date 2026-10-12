-- =============================================================================
-- Part 4: Semantic View + Cortex Analyst 構築
-- =============================================================================
-- Dynamic Tables に対して Semantic View（メタデータ定義）を作成し、
-- 自然言語で SQL を自動生成・実行できる環境を構築します。
-- Semantic View は Cortex Analyst / Cortex Agent のバックエンドとして機能します。
--
-- テーブル定義:
--   INCIDENTS         : インシデント詳細（DT_INCIDENT_ENRICHED）
--   DAILY_STATS       : 日別統計（DT_INCIDENT_DAILY_STATS）
--   SLA_ANALYSIS      : SLA分析（DT_SLA_ANALYSIS）
--   TEAM_PERFORMANCE  : チーム別実績（DT_TEAM_PERFORMANCE）
--   EVENT_LOGS        : ITイベントログ（IT_EVENT_LOGS, 5000万件）
--   EVENT_CORRELATION : イベント×インシデント突合（DT_EVENT_INCIDENT_CORRELATION）
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW

  -- ===== テーブル定義（PRIMARY KEY でテーブルの粒度を明示） =====
  TABLES (
    incidents AS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
      PRIMARY KEY (sys_id)
      COMMENT = 'インシデント詳細テーブル（1行=1インシデント）',
    daily_stats AS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS
      PRIMARY KEY (report_date)
      COMMENT = '日別インシデント統計（1行=1日）',
    sla_analysis AS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
      PRIMARY KEY (sla_record_id)
      COMMENT = 'SLA達成状況分析テーブル（1行=1SLAレコード）',
    team_performance AS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
      PRIMARY KEY (assignment_group)
      COMMENT = 'チーム別パフォーマンスサマリー（1行=1チーム）',
    event_logs AS SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
      PRIMARY KEY (event_id)
      COMMENT = 'ITインフラ イベントログ（1行=1イベント、5000万件）',
    event_correlation AS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
      PRIMARY KEY (event_date, category)
      COMMENT = 'イベント×インシデント突合サマリー（日別カテゴリ別）'
  )

  -- ===== リレーション（テーブル間の結合条件を定義） =====
  RELATIONSHIPS (
    incidents_to_daily AS
      incidents (opened_at) REFERENCES daily_stats (report_date),
    correlation_to_incidents AS
      event_correlation (category) REFERENCES incidents (category),
    event_logs_to_correlation AS
      event_logs (category) REFERENCES event_correlation (category)
  )

  -- ===== ディメンション（分析軸: カテゴリ、日付、チーム等） =====
  DIMENSIONS (
    -- incidents テーブル
    incidents.dim_incident_number AS incident_number
      COMMENT = 'インシデント番号（例: INC0000001）',
    incidents.dim_short_description AS short_description
      COMMENT = 'インシデントの概要説明',
    incidents.dim_category AS category
      COMMENT = 'インシデントのカテゴリ（network, software, hardware, inquiry, database 等）',
    incidents.dim_priority_label AS priority_label
      COMMENT = '優先度ラベル（1 - Critical, 2 - High, 3 - Moderate, 4 - Low, 5 - Planning）',
    incidents.dim_state_label AS state_label
      COMMENT = 'インシデントの状態（New, In Progress, On Hold, Resolved, Closed, Canceled）',
    incidents.dim_assignment_group AS assignment_group_name
      COMMENT = '担当チーム名',
    incidents.dim_assigned_to AS assigned_to_name
      COMMENT = '担当者の名前',
    incidents.dim_opened_at AS opened_at
      COMMENT = 'インシデントがオープンされた日時',
    incidents.dim_resolved_at AS resolved_at
      COMMENT = 'インシデントが解決された日時',
    -- daily_stats テーブル
    daily_stats.dim_report_date AS report_date
      COMMENT = 'レポート日付',
    daily_stats.dim_day_of_week AS day_of_week
      COMMENT = '曜日',
    daily_stats.dim_top_category AS top_category
      COMMENT = 'その日で最も多いインシデントカテゴリ',
    -- sla_analysis テーブル
    sla_analysis.dim_incident_number AS incident_number
      COMMENT = 'SLAに関連するインシデント番号',
    sla_analysis.dim_stage AS stage
      COMMENT = 'SLAの進捗ステージ（achieved, breached, in_progress, cancelled, paused）',
    sla_analysis.dim_has_breached AS has_breached
      COMMENT = 'SLA違反フラグ',
    -- team_performance テーブル
    team_performance.dim_team_name AS assignment_group
      COMMENT = '担当チーム名',
    team_performance.dim_top_category AS top_category
      COMMENT = 'チームで最も多く対応するカテゴリ',
    -- event_logs テーブル（5000万件のイベントログ）
    event_logs.dim_server_name AS server_name
      COMMENT = 'サーバー名（app-server-01 等）',
    event_logs.dim_event_type AS event_type
      COMMENT = 'イベント種別（INFO, WARNING, ERROR, CRITICAL）',
    event_logs.dim_category AS category
      COMMENT = 'イベントカテゴリ（network, software, hardware, inquiry, database）',
    event_logs.dim_timestamp AS timestamp
      COMMENT = 'イベント発生日時',
    event_logs.dim_source_ip AS source_ip
      COMMENT = 'イベント発生元IPアドレス',
    -- event_correlation テーブル（イベント×インシデント突合）
    event_correlation.dim_event_date AS event_date
      COMMENT = '突合日付',
    event_correlation.dim_category AS category
      COMMENT = '突合カテゴリ'
  )

  -- ===== メトリクス（集計指標: COUNT, SUM, AVG 等） =====
  METRICS (
    -- incidents テーブル
    incidents.avg_mttr AS AVG(mttr_hours)
      COMMENT = '平均復旧時間（MTTR、時間単位）',
    incidents.incident_count AS COUNT(*)
      COMMENT = 'インシデント件数',
    -- daily_stats テーブル
    daily_stats.ds_total_incidents AS SUM(total_incidents)
      COMMENT = '総インシデント発生件数',
    daily_stats.ds_resolved_incidents AS SUM(resolved_incidents)
      COMMENT = '解決済みインシデント件数',
    daily_stats.ds_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = '日別平均MTTR（時間）',
    daily_stats.ds_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = '日別SLA遵守率（%）',
    -- sla_analysis テーブル
    sla_analysis.sla_record_count AS COUNT(*)
      COMMENT = 'SLAレコード件数',
    sla_analysis.sla_avg_percentage AS AVG(percentage)
      COMMENT = 'SLA平均消費率',
    -- team_performance テーブル
    team_performance.team_total_incidents AS SUM(total_incidents)
      COMMENT = 'チーム総インシデント件数',
    team_performance.team_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'チーム平均MTTR（時間）',
    team_performance.team_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = 'チームSLA遵守率（%）',
    -- event_logs テーブル
    event_logs.event_log_count AS COUNT(*)
      COMMENT = 'イベントログ件数',
    event_logs.critical_event_count AS COUNT_IF(event_type = 'CRITICAL')
      COMMENT = 'CRITICALイベント件数',
    event_logs.error_event_count AS COUNT_IF(event_type = 'ERROR')
      COMMENT = 'ERRORイベント件数',
    -- event_correlation テーブル
    event_correlation.total_events AS SUM(event_count)
      COMMENT = '突合集計：イベント総数',
    event_correlation.total_critical_events AS SUM(critical_event_count)
      COMMENT = '突合集計：CRITICALイベント数',
    event_correlation.total_incidents AS SUM(incident_count)
      COMMENT = '突合集計：インシデント数',
    event_correlation.corr_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = '突合集計：平均MTTR（時間）'
  )

  COMMENT = 'ServiceNow IT運用データ + ITインフラ イベントログのSemantic View'

  -- ===== Cortex Analyst カスタム指示 =====
  AI_SQL_GENERATION '日本語で質問された場合は、日本語でカラムのエイリアスをつけてください。数値は小数点2桁で丸めてください。VQRのSQLではdim_プレフィックス付きのカラム名を使用し、エイリアスにはASCII文字のみを使用してください。'

  -- ===== 検証済みクエリ（VQR）: Cortex Analyst の精度向上に使用 =====
  AI_VERIFIED_QUERIES (
    category_mttr AS (
      QUESTION 'カテゴリ別のMTTRは？'
      SQL 'SELECT dim_category AS category, ROUND(AVG(mttr_hours), 2) AS avg_mttr, COUNT(*) AS incident_count FROM __incidents WHERE mttr_hours IS NOT NULL AND dim_category IS NOT NULL AND dim_category != '''' GROUP BY dim_category ORDER BY avg_mttr DESC'
    ),
    top_team AS (
      QUESTION '最もインシデントが多いチームは？'
      SQL 'SELECT dim_team_name AS team, total_incidents, avg_mttr_hours, sla_compliance_pct FROM __team_performance ORDER BY total_incidents DESC LIMIT 10'
    ),
    sla_breach AS (
      QUESTION 'SLA違反の件数は？'
      SQL 'SELECT dim_stage AS stage, COUNT(*) AS record_count, COUNT(CASE WHEN dim_has_breached = TRUE THEN 1 END) AS breached_count FROM __sla_analysis GROUP BY dim_stage ORDER BY record_count DESC'
    ),
    priority_sla AS (
      QUESTION '優先度別のSLA遵守率は？'
      SQL 'SELECT priority_label, COUNT(*) AS total, COUNT(CASE WHEN sla_met = TRUE THEN 1 END) AS sla_met_count, ROUND(COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0), 2) AS sla_compliance_pct FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED WHERE sla_met IS NOT NULL GROUP BY priority_label ORDER BY priority_label'
    ),
    event_log_summary AS (
      QUESTION 'イベントログの総件数は？'
      SQL 'SELECT COUNT(*) AS total_events, COUNT_IF(dim_event_type = ''CRITICAL'') AS critical_events, COUNT_IF(dim_event_type = ''ERROR'') AS error_events FROM __event_logs'
    ),
    event_category_summary AS (
      QUESTION 'カテゴリ別のイベント数とインシデント数の比較は？'
      SQL 'SELECT dim_category AS category, SUM(event_count) AS total_events, SUM(critical_event_count) AS critical_events, SUM(incident_count) AS incidents, ROUND(AVG(avg_mttr_hours), 2) AS avg_mttr FROM __event_correlation GROUP BY dim_category ORDER BY total_events DESC'
    )
  );

-- -----------------------------------------------------------------------------
-- 確認
-- -----------------------------------------------------------------------------
SHOW SEMANTIC VIEWS IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;
DESCRIBE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;
