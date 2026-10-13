# Part 1.5: AWS S3 からのデータロード（外部データ連携）

## 概要

AWS S3 に配置された IT インフラ イベントログ（5,000万行、約2GB × 10ファイル）を Snowflake にロードします。ウェアハウスサイズの変更によるロードパフォーマンスの違いも体験します。

## 前提条件

- Part 1 が完了し、ServiceNow データが同期済み
- 講師が事前に S3 バケットにイベントログファイルを配置済み

## このパートで学ぶこと

- External Stage を使った S3 からのデータロード（COPY INTO）
- ウェアハウスサイズとロードパフォーマンスの関係
- 外部データと ServiceNow データの突合分析

---

## Step 1: ロード先テーブルの作成

```sql
-- =============================================
-- Step 1: イベントログテーブルの作成
-- =============================================
USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

CREATE OR REPLACE TABLE IT_EVENT_LOGS (
    event_id        STRING,
    timestamp       TIMESTAMP_NTZ,
    server_name     STRING,
    event_type      STRING,
    severity        INT,
    category        STRING,
    description     STRING,
    source_ip       STRING
);
```

---

## Step 2: Storage Integration の作成

Snowflake から S3 バケットへのアクセスを許可する Storage Integration を作成します。

```sql
-- =============================================
-- Step 2: Storage Integration の作成
-- =============================================
CREATE OR REPLACE STORAGE INTEGRATION s3_handson_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::484577546576:role/oist-handson-snowflake-s3-role'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('s3://oist-handson/handson/');
```

### IAM 信頼ポリシーの設定（講師が事前に実施）

```sql
-- Snowflake 側の情報を確認
DESC INTEGRATION s3_handson_integration;
```

出力される `STORAGE_AWS_IAM_USER_ARN` と `STORAGE_AWS_EXTERNAL_ID` を AWS IAM ロールの信頼ポリシーに設定します（講師が事前に設定済み）。

---

## Step 3: External Stage の作成

```sql
-- =============================================
-- Step 3: External Stage の作成
-- =============================================
CREATE OR REPLACE STAGE SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE
  STORAGE_INTEGRATION = s3_handson_integration
  URL = 's3://oist-handson/handson/'
  FILE_FORMAT = (
    TYPE = CSV
    COMPRESSION = GZIP
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  );
```

### ファイルの確認

```sql
-- S3 上のファイルを確認
LIST @SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE;
```

---

## Step 4: ウェアハウスサイズによるパフォーマンス比較

ウェアハウスのサイズを変更するだけで、データロードのパフォーマンスが向上することを体験します。

### 4.1 XS（X-Small）ウェアハウスでロード

```sql
-- =============================================
-- Step 4.1: XS ウェアハウスでロード
-- =============================================
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

-- ロード実行（所要時間を確認）
COPY INTO SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
  FROM @SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE
  PATTERN = '.*it_event_logs_[0-9]+\\.csv\\.gz';
```

> **確認**: Query History でロード時間を記録してください。参考値：約30秒

```sql
-- ロード結果の確認
SELECT COUNT(*) AS row_count FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
SELECT * FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS LIMIT 5;
```

### 4.2 テーブルをクリアして再ロード準備

```sql
-- テーブルをクリア
TRUNCATE TABLE SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;

-- クリア確認（0行であること）
SELECT COUNT(*) AS row_count FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
```

### 4.3 M（Medium）ウェアハウスでロード

```sql
-- =============================================
-- Step 4.3: M ウェアハウスでロード
-- =============================================
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'MEDIUM';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

-- ロード実行（所要時間を確認）
COPY INTO SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
  FROM @SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE
  PATTERN = '.*it_event_logs_[0-9]+\\.csv\\.gz';
```

> **確認**: Query History でロード時間を記録してください。参考値：約14秒

### パフォーマンス比較結果（参考値）

| ウェアハウスサイズ | 実行時間 | 行数 |
|---|---|---|
| **X-Small** | 約30秒 | 50,000,000 |
| **Medium** | 約14秒 | 50,000,000 |

> **ポイント**: M は XS の約2倍高速です。Snowflake は10ファイルを並列にロードしますが、XS は1ノードで順次処理するのに対し、M は複数ノードで並列処理するためパフォーマンスが向上します。SQL やファイルの分割などの作業は不要で、ウェアハウスサイズを変えるだけです。

### 4.4 ウェアハウスを元に戻す

```sql
-- コスト節約のため XS に戻す
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
```

---

## Step 5: ロードデータの確認

```sql
-- =============================================
-- Step 5: データ確認
-- =============================================

-- 件数確認
SELECT COUNT(*) AS total_rows FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;

-- サンプルデータ
SELECT * FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS LIMIT 10;

-- カテゴリ別集計
SELECT
    category,
    COUNT(*) AS event_count,
    COUNT(CASE WHEN event_type = 'CRITICAL' THEN 1 END) AS critical_count,
    MIN(timestamp) AS earliest,
    MAX(timestamp) AS latest
FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
GROUP BY category
ORDER BY event_count DESC;
```

---

## Step 6: イベントログ × インシデント 突合分析用 Dynamic Table

```sql
-- =============================================
-- Step 6: 突合分析用 Dynamic Table の作成
-- =============================================
CREATE OR REPLACE DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    DATE_TRUNC('day', e.timestamp)::DATE AS event_date,
    e.category,
    COUNT(DISTINCT e.event_id) AS event_count,
    COUNT(DISTINCT CASE WHEN e.event_type = 'CRITICAL' THEN e.event_id END) AS critical_event_count,
    COUNT(DISTINCT CASE WHEN e.event_type = 'ERROR' THEN e.event_id END) AS error_event_count,
    COUNT(DISTINCT i.sys_id) AS incident_count,
    ROUND(AVG(i.mttr_hours), 2) AS avg_mttr_hours
FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS e
LEFT JOIN SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED i
    ON e.category = i.category
    AND DATE_TRUNC('day', e.timestamp) = DATE_TRUNC('day', i.opened_at)
GROUP BY 1, 2;
```

> **解説**:
> - イベントログとインシデントを `category`（カテゴリ）と `日付` で突合
> - 「イベント多発日にインシデントも多いか？」「CRITICAL イベントとインシデントの相関は？」を分析可能

---

## まとめ

このパートで実施したこと：

1. **S3 外部データ連携**: Storage Integration + External Stage でセキュアにアクセス
2. **COPY INTO でバルクロード**: 5,000万行のイベントログを10ファイル並列で一括ロード
3. **ウェアハウスサイズの効果**: XS（約30秒）→ M（約14秒）で約2倍のパフォーマンス向上を実証
4. **外部データとの突合**: イベントログ × ServiceNow インシデントの相関分析用 Dynamic Table を作成

> **ポイント**: Snowflake は SQL を変えずにウェアハウスサイズを変更するだけでパフォーマンスが向上します。データ量の増加に対してはインフラのチューニングではなく、ウェアハウスの「T シャツサイズ」を変えるだけで対応できます。

**次のパート**: [Part 2: Dynamic Tables でデータ加工](part2_dynamic_tables.md) に進みます。
