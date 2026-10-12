# Part 2: Dynamic Tables でデータ加工パイプライン構築

## 概要

このパートでは、ServiceNow Connector で同期された生データを Dynamic Tables を使って分析しやすい形に変換します。Dynamic Tables は宣言的なデータパイプラインで、ソースデータが更新されると自動的にリフレッシュされます。

## 前提条件

- Part 1 が完了し、以下のテーブルが同期済み：
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT`
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER`
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP`
  - `SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA`

> **注意**: Connector が同期したテーブルは VARIANT 形式（`RAW` カラム）で格納されています。Dynamic Tables で `RAW:field::TYPE` 構文を使ってフラット化します。

---

## Step 1: ハンズオン用データベース・スキーマの作成

```sql
-- =============================================
-- Step 1: 分析用データベース・スキーマの作成
-- =============================================
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS SERVICENOW_HANDSON;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS;
```

> **解説**: 同期データ（`SERVICENOW_DEST_DB`）と分析用テーブル（`SERVICENOW_HANDSON`）を分離することで、役割を明確にします。

---

## Step 2: Dynamic Table 1 — インシデント詳細テーブル

インシデントデータとユーザー・グループデータを結合し、MTTR（平均復旧時間）と SLA 遵守判定を計算します。

```sql
-- =============================================
-- Step 2: DT_INCIDENT_ENRICHED
-- インシデント × ユーザー × グループ結合、MTTR・SLA 計算
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
    -- 優先度のラベルマッピング
    CASE i.RAW:priority::STRING
        WHEN '1' THEN '1 - Critical'
        WHEN '2' THEN '2 - High'
        WHEN '3' THEN '3 - Moderate'
        WHEN '4' THEN '4 - Low'
        WHEN '5' THEN '5 - Planning'
        ELSE i.RAW:priority::STRING
    END                                                AS priority_label,
    -- ステータスのラベルマッピング
    CASE i.RAW:state::STRING
        WHEN '1' THEN 'New'
        WHEN '2' THEN 'In Progress'
        WHEN '3' THEN 'On Hold'
        WHEN '6' THEN 'Resolved'
        WHEN '7' THEN 'Closed'
        WHEN '8' THEN 'Canceled'
        ELSE i.RAW:state::STRING
    END                                                AS state_label,
    -- グループ情報（sys_user_group と結合）
    i.RAW:assignment_group:value::STRING               AS assignment_group_id,
    g.RAW:name::STRING                                 AS assignment_group_name,
    -- 担当者情報（sys_user と結合）
    i.RAW:assigned_to:value::STRING                    AS assigned_to_id,
    u.RAW:name::STRING                                 AS assigned_to_name,
    u.RAW:email::STRING                                AS assigned_to_email,
    -- 日時（空文字列を安全にタイムスタンプ変換）
    TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING)     AS opened_at,
    TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)   AS resolved_at,
    TRY_TO_TIMESTAMP_NTZ(i.RAW:closed_at::STRING)     AS closed_at,
    -- MTTR（解決までの時間）を時間単位で計算
    CASE
        WHEN NULLIF(i.RAW:resolved_at::STRING, '') IS NOT NULL
         AND NULLIF(i.RAW:opened_at::STRING, '') IS NOT NULL
        THEN ROUND(DATEDIFF('minute',
               TRY_TO_TIMESTAMP_NTZ(i.RAW:opened_at::STRING),
               TRY_TO_TIMESTAMP_NTZ(i.RAW:resolved_at::STRING)) / 60.0, 2)
        ELSE NULL
    END                                                AS mttr_hours,
    -- SLA 遵守判定（P1=4h, P2=8h, P3=24h, P4=72h）
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

> **解説**:
> - Connector が同期するデータは `RAW` カラム（VARIANT 型）に格納されます。`RAW:field::TYPE` でフラット化します
> - 参照フィールド（`assigned_to`, `assignment_group`）は `{value: "sys_id", link: "..."}` のオブジェクト構造。`RAW:assigned_to:value::STRING` で sys_id を取得し、`SYS_USER` / `SYS_USER_GROUP` テーブルと結合
> - 空文字列がタイムスタンプ変換でエラーになるため、`TRY_TO_TIMESTAMP_NTZ` と `NULLIF` を使用
> - **MTTR**: `OPENED_AT` から `RESOLVED_AT` までの差分を時間単位で計算
> - **SLA 遵守判定**: 優先度ごとに解決時間の閾値を設定（P1: 4h, P2: 8h, P3: 24h, P4: 72h）
> - `TARGET_LAG = '1 hour'`: ソースデータ更新後、最大 1 時間以内にリフレッシュ

---

## Step 3: Dynamic Table 2 — 日別インシデント統計

```sql
-- =============================================
-- Step 3: DT_INCIDENT_DAILY_STATS
-- 日別のインシデント集計
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

> **解説**:
> - 日ごとのインシデント発生件数、解決件数、オープン件数を集計
> - `sla_compliance_pct`: SLA 遵守率（%）
> - `top_category`: その日で最も多いカテゴリ
> - このテーブルは `DT_INCIDENT_ENRICHED` を参照するため、パイプラインとして連鎖します

---

## Step 4: Dynamic Table 3 — SLA 分析テーブル

```sql
-- =============================================
-- Step 4: DT_SLA_ANALYSIS
-- task_sla テーブルからSLA達成状況を分析
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

> **解説**:
> - `task_sla` テーブルと `incident` テーブルを結合し、SLA レコードにインシデント情報を付加
> - `stage`: SLA の進捗状態（`achieved`, `breached`, `in_progress`, `cancelled` 等）
> - `has_breached`: SLA が違反されたかどうか
> - `percentage`: SLA の消費率（100% 超 = 違反）

---

## Step 5: Dynamic Table 4 — チーム別パフォーマンス

```sql
-- =============================================
-- Step 5: DT_TEAM_PERFORMANCE
-- チーム（Assignment Group）別のパフォーマンス指標
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

> **解説**:
> - チーム（Assignment Group）ごとのインシデント対応実績を集計
> - `avg_mttr_hours`: チーム別の平均解決時間
> - `sla_compliance_pct`: チーム別の SLA 遵守率
> - `high_priority_count`: 高優先度（P1, P2）インシデントの件数

---

## Step 6: Dynamic Tables の確認

### 6.1 Dynamic Tables の一覧確認

```sql
-- =============================================
-- Step 6.1: Dynamic Tables の一覧と状態確認
-- =============================================
SHOW DYNAMIC TABLES IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;
```

### 6.2 手動リフレッシュの実行

```sql
-- =============================================
-- Step 6.2: 手動リフレッシュ
-- =============================================
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED REFRESH;
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS REFRESH;
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS REFRESH;
ALTER DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE REFRESH;
```

> **解説**: `ALTER DYNAMIC TABLE ... REFRESH` で即時リフレッシュを実行できます。通常は `TARGET_LAG` に基づいて自動リフレッシュされますが、ハンズオン中はデータをすぐ確認するために手動実行します。

### 6.3 データ確認

```sql
-- =============================================
-- Step 6.3: 各テーブルのデータ確認
-- =============================================

-- インシデント詳細
SELECT incident_number, short_description, priority_label, state_label,
       assignment_group_name, assigned_to_name, mttr_hours, sla_met
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
LIMIT 10;

-- 日別統計
SELECT report_date, total_incidents, resolved_incidents, avg_mttr_hours, sla_compliance_pct
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS
ORDER BY report_date DESC
LIMIT 10;

-- SLA 分析
SELECT incident_number, incident_description, stage, has_breached, percentage, duration_hours
FROM SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
LIMIT 10;

-- チーム別パフォーマンス
SELECT assignment_group, total_incidents, avg_mttr_hours, sla_compliance_pct
FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
ORDER BY total_incidents DESC;
```

---

## パイプラインの構造

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

> **ポイント**: Dynamic Tables は宣言的パイプラインです。SQL の SELECT 文でロジックを定義するだけで、データの自動更新・依存関係の管理は Snowflake が行います。`TARGET_LAG` を設定するだけでリフレッシュスケジュールの管理が不要になります。

---

## まとめ

このパートで実施したこと：

1. 分析用データベース・スキーマ（`SERVICENOW_HANDSON.ANALYTICS`）を作成
2. 4 つの Dynamic Tables を作成：
   - `DT_INCIDENT_ENRICHED`: インシデント詳細（ユーザー・グループ結合、MTTR、SLA 判定）
   - `DT_INCIDENT_DAILY_STATS`: 日別インシデント統計
   - `DT_SLA_ANALYSIS`: SLA 達成状況分析（task_sla テーブル活用）
   - `DT_TEAM_PERFORMANCE`: チーム別パフォーマンス
3. 手動リフレッシュとデータ確認を実施

**次のパート**: [Part 3: Snowflake Notebooks で分析・可視化](part3_analysis_notebook.md) に進みます。
