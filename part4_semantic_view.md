# Part 4: Semantic View + Cortex Analyst 構築

## 概要

このパートでは、Part 2 で作成した Dynamic Tables に対して Semantic View を定義し、自然言語でデータに問い合わせできる環境を構築します。Semantic View は Cortex Analyst のバックエンドとして機能し、Part 5 の AI エージェントアプリからも利用します。

## 前提条件

- Part 2 が完了し、以下の Dynamic Tables にデータが存在：
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE`
- Part 1.5 が完了し、以下のテーブルにデータが存在：
  - `SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS`（5,000万行のイベントログ）
  - `SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION`（イベント×インシデント突合）

---

## Step 1: Semantic View の概念

Semantic View は、テーブルやビューに対して以下のメタデータを定義するオブジェクトです：

- **テーブル（Tables）**: 分析対象のテーブルを論理名で定義
- **ディメンション（Dimensions）**: 分析軸（カテゴリ、日付、チーム等）
- **メトリクス（Metrics）**: 集計指標（COUNT, SUM, AVG 等）
- **リレーション（Relationships）**: テーブル間の結合条件
- **VQR（Verified Queries）**: 検証済みクエリ（Cortex Analyst の精度向上に使用）

これにより、Cortex Analyst は自然言語の質問を正確な SQL に変換できるようになります。

---

## Step 2: Semantic View の作成

以下の SQL を実行して Semantic View を作成します。

```sql
-- =============================================
-- Step 2: Semantic View の作成
-- =============================================
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

  -- ===== リレーション =====
  RELATIONSHIPS (
    incidents_to_daily AS
      incidents (opened_at) REFERENCES daily_stats (report_date),
    correlation_to_incidents AS
      event_correlation (category) REFERENCES incidents (category),
    event_logs_to_correlation AS
      event_logs (category) REFERENCES event_correlation (category)
  )

  -- ===== ディメンション =====
  DIMENSIONS (
    -- incidents テーブルのディメンション
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
    -- daily_stats テーブルのディメンション
    daily_stats.dim_report_date AS report_date
      COMMENT = 'レポート日付',
    daily_stats.dim_day_of_week AS day_of_week
      COMMENT = '曜日',
    daily_stats.dim_top_category AS top_category
      COMMENT = 'その日で最も多いインシデントカテゴリ',
    -- sla_analysis テーブルのディメンション
    sla_analysis.dim_incident_number AS incident_number
      COMMENT = 'SLAに関連するインシデント番号',
    sla_analysis.dim_stage AS stage
      COMMENT = 'SLAの進捗ステージ（achieved, breached, in_progress, cancelled, paused）',
    sla_analysis.dim_has_breached AS has_breached
      COMMENT = 'SLA違反フラグ',
    -- team_performance テーブルのディメンション
    team_performance.dim_team_name AS assignment_group
      COMMENT = '担当チーム名',
    team_performance.dim_top_category AS top_category
      COMMENT = 'チームで最も多く対応するカテゴリ',
    -- event_logs テーブルのディメンション
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
    -- event_correlation テーブルのディメンション
    event_correlation.dim_event_date AS event_date
      COMMENT = '突合日付',
    event_correlation.dim_category AS category
      COMMENT = '突合カテゴリ'
  )

  -- ===== メトリクス =====
  METRICS (
    -- incidents テーブルのメトリクス
    incidents.avg_mttr AS AVG(mttr_hours)
      COMMENT = '平均復旧時間（MTTR、時間単位）',
    incidents.incident_count AS COUNT(*)
      COMMENT = 'インシデント件数',
    -- daily_stats テーブルのメトリクス
    daily_stats.ds_total_incidents AS SUM(total_incidents)
      COMMENT = '総インシデント発生件数',
    daily_stats.ds_resolved_incidents AS SUM(resolved_incidents)
      COMMENT = '解決済みインシデント件数',
    daily_stats.ds_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = '日別平均MTTR（時間）',
    daily_stats.ds_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = '日別SLA遵守率（%）',
    -- sla_analysis テーブルのメトリクス
    sla_analysis.sla_record_count AS COUNT(*)
      COMMENT = 'SLAレコード件数',
    sla_analysis.sla_avg_percentage AS AVG(percentage)
      COMMENT = 'SLA平均消費率',
    -- team_performance テーブルのメトリクス
    team_performance.team_total_incidents AS SUM(total_incidents)
      COMMENT = 'チーム総インシデント件数',
    team_performance.team_avg_mttr AS AVG(avg_mttr_hours)
      COMMENT = 'チーム平均MTTR（時間）',
    team_performance.team_sla_compliance AS AVG(sla_compliance_pct)
      COMMENT = 'チームSLA遵守率（%）',
    -- event_logs テーブルのメトリクス
    event_logs.event_log_count AS COUNT(*)
      COMMENT = 'イベントログ件数',
    event_logs.critical_event_count AS COUNT_IF(event_type = 'CRITICAL')
      COMMENT = 'CRITICALイベント件数',
    event_logs.error_event_count AS COUNT_IF(event_type = 'ERROR')
      COMMENT = 'ERRORイベント件数',
    -- event_correlation テーブルのメトリクス
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
  AI_SQL_GENERATION '日本語で質問された場合は、日本語でカラムのエイリアスをつけてください。数値は小数点2桁で丸めてください。'

  -- ===== 検証済みクエリ（VQR） =====
  AI_VERIFIED_QUERIES (
    category_mttr AS (
      QUESTION 'カテゴリ別のMTTRは？'
      SQL 'SELECT category,
                 ROUND(AVG(mttr_hours), 2) AS avg_mttr_hours,
                 COUNT(*) AS incident_count
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
          WHERE mttr_hours IS NOT NULL AND category IS NOT NULL AND category != ''''
          GROUP BY category
          ORDER BY avg_mttr_hours DESC'
    ),
    top_team AS (
      QUESTION '最もインシデントが多いチームは？'
      SQL 'SELECT assignment_group,
                 total_incidents,
                 avg_mttr_hours,
                 sla_compliance_pct
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
          ORDER BY total_incidents DESC
          LIMIT 10'
    ),
    sla_breach AS (
      QUESTION 'SLA違反の件数は？'
      SQL 'SELECT stage,
            COUNT(*) AS record_count,
            COUNT(CASE WHEN has_breached = TRUE THEN 1 END) AS breached_count
          FROM SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
          GROUP BY stage
          ORDER BY record_count DESC'
    ),
    priority_sla AS (
      QUESTION '優先度別のSLA遵守率は？'
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
      QUESTION 'イベントログの総件数は？'
      SQL 'SELECT COUNT(*) AS total_events, COUNT_IF(dim_event_type = ''CRITICAL'') AS critical_events, COUNT_IF(dim_event_type = ''ERROR'') AS error_events FROM __event_logs'
    ),
    event_category_summary AS (
      QUESTION 'カテゴリ別のイベント数とインシデント数の比較は？'
      SQL 'SELECT dim_category AS category, SUM(event_count) AS total_events, SUM(critical_event_count) AS critical_events, SUM(incident_count) AS incidents, ROUND(AVG(avg_mttr_hours), 2) AS avg_mttr FROM __event_correlation GROUP BY dim_category ORDER BY total_events DESC'
    )
  );
```

> **解説**:
> - **DDL 構文**: `CREATE SEMANTIC VIEW` は `TABLES`, `RELATIONSHIPS`, `DIMENSIONS`, `METRICS` の順で定義します
> - `<table_alias>.<semantic_name> AS <sql_expression>` の形式でディメンション・メトリクスを定義
> - `AI_SQL_GENERATION`: Cortex Analyst に対する SQL 生成時の指示（日本語エイリアス等）
> - `AI_VERIFIED_QUERIES`: よくある質問と正しい SQL のペアを定義し、Cortex Analyst の精度を向上

---

## Step 3: Semantic View の確認

```sql
-- =============================================
-- Step 3: Semantic View の確認
-- =============================================

-- Semantic View の一覧
SHOW SEMANTIC VIEWS IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- Semantic View の詳細
DESCRIBE SEMANTIC VIEW SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;
```

---

## Step 4: Cortex Analyst で自然言語クエリのテスト

### 4.1 Snowsight での実行方法

1. Snowsight にログイン
2. 左メニューから **AI & ML > Cortex Analyst** を選択
3. Semantic View として `SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW` を選択
4. 以下のような質問を入力してテスト

### 4.2 テスト質問例

#### 質問 1: カテゴリ分析（VQR あり）
```
カテゴリ別の平均MTTRを教えて
```

#### 質問 2: チーム比較（VQR あり）
```
最もインシデントが多いチームトップ5は？
```

#### 質問 3: SLA 分析（VQR あり）
```
SLA違反の件数は？
```

#### 質問 4: 優先度別 SLA（VQR あり）
```
優先度別のSLA遵守率を見せて
```

#### 質問 5: イベントログ件数（VQR あり）
```
イベントログの総件数は？
```

#### 質問 6: イベント×インシデント相関（VQR あり）
```
カテゴリ別のイベント数とインシデント数の比較は？
```

#### 質問 7: 応用（VQR に無い質問）
```
今月のインシデントで最も多いカテゴリは何？
```

#### 質問 8: 時系列分析
```
直近6ヶ月のインシデント件数の推移を月別に見せて
```

> **ポイント**: VQR（検証済みクエリ）に定義した質問は高精度で回答されます。VQR に無い質問も、ディメンション・メトリクスの定義とコメントを基に SQL が生成されますが、精度が低い場合は VQR を追加して改善できます。

---

## Step 5: Cortex Analyst を SQL から呼び出す（オプション）

プログラムから Cortex Analyst を呼び出す方法も確認しておきましょう。

```sql
-- =============================================
-- Step 5: SQL からの Cortex Analyst 呼び出し
-- =============================================

-- 自然言語クエリを SQL に変換して実行
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'claude-3-5-sonnet',
  'カテゴリ別のMTTRを教えて'
);
```

> **解説**: Cortex Analyst は Snowsight UI や Cortex Agent 経由で利用するのが一般的です。Part 5 では Cortex Agent を通じて Semantic View を活用します。

---

## まとめ

このパートで実施したこと：

1. Semantic View の概念（テーブル、ディメンション、メトリクス、リレーション、VQR）を理解
2. 6 つのテーブルを持つ Semantic View を作成：
   - `incidents`: インシデント詳細
   - `daily_stats`: 日別統計
   - `sla_analysis`: SLA 分析
   - `team_performance`: チーム別パフォーマンス
   - `event_logs`: ITインフラ イベントログ（5,000万件）
   - `event_correlation`: イベント×インシデント突合サマリー
3. 6 つの VQR（検証済みクエリ）を設定（インシデント分析 + イベントログ分析）
4. Cortex Analyst で自然言語クエリをテスト

**次のパート**: [Part 5: AI エージェントアプリ (App Runtime) 構築](part5_ai_agent_app.md) に進みます。
