-- =============================================================================
-- Part 1.5: AWS S3 からのデータロード（外部データ連携）
-- =============================================================================
-- S3 に配置された IT インフラ イベントログ（5,000万行、10ファイル）を Snowflake にロードし、
-- ウェアハウスサイズによるパフォーマンスの違いを体験します。
--
-- AWS 連携情報:
--   AWS アカウント ID : 484577546576
--   IAM ロール        : oist-handson-snowflake-s3-role
--   S3 バケット       : s3://oist-handson/handson/ (ap-northeast-1)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- -----------------------------------------------------------------------------
-- Step 1: イベントログテーブルの作成
-- S3 からロードするデータの受け皿となるテーブル
-- カラム: イベントID、タイムスタンプ、サーバー名、イベント種別、重要度、カテゴリ、説明、送信元IP
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE IT_EVENT_LOGS (
    event_id        STRING,
    timestamp       TIMESTAMP_NTZ,
    server_name     STRING,
    event_type      STRING,      -- INFO, WARNING, ERROR, CRITICAL
    severity        INT,         -- 1=CRITICAL, 2=ERROR, 3=WARNING, 4=INFO
    category        STRING,      -- network, software, hardware, inquiry, database
    description     STRING,
    source_ip       STRING
);

-- -----------------------------------------------------------------------------
-- Step 2: Storage Integration の作成
-- Snowflake が AWS IAM ロールを使って S3 バケットにアクセスするための設定
-- 作成後、DESC INTEGRATION で表示される IAM_USER_ARN と EXTERNAL_ID を
-- AWS 側の IAM ロール信頼ポリシーに設定する必要がある（講師が事前に設定済み）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE STORAGE INTEGRATION s3_handson_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::484577546576:role/oist-handson-snowflake-s3-role'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('s3://oist-handson/handson/');

-- Snowflake 側の情報を確認（AWS IAM 信頼ポリシーに必要）
DESC INTEGRATION s3_handson_integration;

-- -----------------------------------------------------------------------------
-- Step 3: External Stage の作成
-- Storage Integration を使って S3 バケットを Snowflake のステージとしてマウント
-- FILE_FORMAT でCSV形式・GZIP圧縮・ヘッダースキップを指定
-- -----------------------------------------------------------------------------
CREATE OR REPLACE STAGE S3_EVENT_STAGE
  STORAGE_INTEGRATION = s3_handson_integration
  URL = 's3://oist-handson/handson/'
  FILE_FORMAT = (
    TYPE = CSV
    COMPRESSION = GZIP
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  );

-- S3 上のファイル一覧を確認（10ファイルが表示されるはず）
LIST @S3_EVENT_STAGE;

-- -----------------------------------------------------------------------------
-- Step 4.1: XS（X-Small）ウェアハウスでロード
-- まず最小サイズのウェアハウスでロード時間を計測する
-- SUSPEND→RESUME でウェアハウスキャッシュをクリアし、公平な比較を行う
-- 参考値: 約30秒
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

COPY INTO IT_EVENT_LOGS
  FROM @S3_EVENT_STAGE
  PATTERN = '.*it_event_logs_[0-9]+\.csv\.gz';

-- Query History でロード時間を記録してください

-- ロード結果の確認
SELECT COUNT(*) AS row_count FROM IT_EVENT_LOGS;
SELECT * FROM IT_EVENT_LOGS LIMIT 5;

-- -----------------------------------------------------------------------------
-- Step 4.2: テーブルをクリアして再ロード準備
-- -----------------------------------------------------------------------------
TRUNCATE TABLE IT_EVENT_LOGS;

-- クリア確認（0行であること）
SELECT COUNT(*) AS row_count FROM IT_EVENT_LOGS;

-- -----------------------------------------------------------------------------
-- Step 4.3: M（Medium）ウェアハウスでロード
-- ウェアハウスサイズを上げて同じデータをロードし、パフォーマンス差を確認
-- 参考値: 約14秒（XSの約2倍高速）
-- Mは4ノードで10ファイルを並列処理するため、XS（1ノード）より高速
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'MEDIUM';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

COPY INTO IT_EVENT_LOGS
  FROM @S3_EVENT_STAGE
  PATTERN = '.*it_event_logs_[0-9]+\.csv\.gz';

-- Query History でロード時間を記録してください

-- -----------------------------------------------------------------------------
-- Step 4.4: ウェアハウスを元に戻す（コスト節約）
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- -----------------------------------------------------------------------------
-- Step 5: ロードデータの確認
-- -----------------------------------------------------------------------------

-- 件数確認（5,000万行が期待値）
SELECT COUNT(*) AS total_rows FROM IT_EVENT_LOGS;

-- サンプルデータ
SELECT * FROM IT_EVENT_LOGS LIMIT 10;

-- カテゴリ別集計
SELECT
    category,
    COUNT(*) AS event_count,
    COUNT(CASE WHEN event_type = 'CRITICAL' THEN 1 END) AS critical_count,
    MIN(timestamp) AS earliest,
    MAX(timestamp) AS latest
FROM IT_EVENT_LOGS
GROUP BY category
ORDER BY event_count DESC;

-- -----------------------------------------------------------------------------
-- Step 6: イベントログ × インシデント 突合分析用 Dynamic Table
-- イベントログとインシデントをカテゴリ+日付で突合し、相関分析を可能にする
-- 「イベント多発日にインシデントも多いか？」「CRITICALイベントとの相関は？」を分析
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE DT_EVENT_INCIDENT_CORRELATION
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
FROM IT_EVENT_LOGS e
LEFT JOIN DT_INCIDENT_ENRICHED i
    ON e.category = i.category
    AND DATE_TRUNC('day', e.timestamp) = DATE_TRUNC('day', i.opened_at)
GROUP BY 1, 2;
