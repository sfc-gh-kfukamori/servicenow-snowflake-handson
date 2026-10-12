-- =============================================================================
-- Part 1: ServiceNow Connector 設定 — Snowflake 側 SQL
-- =============================================================================
-- このスクリプトは ServiceNow Connector の Snowflake 側セットアップ SQL をまとめたものです。
-- ServiceNow 側の OAuth2 設定（Step 1〜2）は手順書（part1_data_loading.md）を参照してください。
--
-- 実行前に以下のプレースホルダーを置き換えてください:
--   <client_id>       : ServiceNow OAuth アプリの Client ID
--   <client_secret>   : ServiceNow OAuth アプリの Client Secret
--   <your-instance>   : ServiceNow PDI のインスタンス名（例: dev181756）
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 3.1: ハンズオン用オブジェクトの作成
-- Connector のデータ保存先と Secret 格納用のデータベース・スキーマを作成
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;

CREATE DATABASE IF NOT EXISTS CONNECTORS_SECRET;
CREATE SCHEMA IF NOT EXISTS CONNECTORS_SECRET.SERVICENOW;

-- -----------------------------------------------------------------------------
-- Step 3.2: Security Integration の作成（OAuth2 Client Credentials 用）
-- Snowflake が ServiceNow に OAuth2 で認証するための設定
-- CLIENT_SECRET_POST: トークン取得時に client_secret を POST ボディに含める方式
-- CLIENT_CREDENTIALS: ユーザー操作なしでトークンを自動取得するグラントタイプ
-- -----------------------------------------------------------------------------
CREATE SECURITY INTEGRATION SERVICENOW_OAUTH2
  TYPE = API_AUTHENTICATION
  AUTH_TYPE = OAUTH2
  OAUTH_CLIENT_AUTH_METHOD = CLIENT_SECRET_POST
  OAUTH_CLIENT_ID = '<client_id>'
  OAUTH_CLIENT_SECRET = '<client_secret>'
  OAUTH_TOKEN_ENDPOINT = 'https://<your-instance>.service-now.com/oauth_token.do'
  OAUTH_GRANT = 'CLIENT_CREDENTIALS'
  OAUTH_ALLOWED_SCOPES = ('useraccount')
  ENABLED = TRUE;

-- -----------------------------------------------------------------------------
-- Step 3.3: OAuth2 Secret の作成
-- Security Integration を参照し、Snowflake がアクセストークンを自動管理する
-- -----------------------------------------------------------------------------
CREATE SECRET CONNECTORS_SECRET.SERVICENOW.SERVICENOW_CREDS
  TYPE = OAUTH2
  API_AUTHENTICATION = SERVICENOW_OAUTH2
  OAUTH_SCOPES = ('useraccount');

-- -----------------------------------------------------------------------------
-- Step 3.4: ネットワークルール作成
-- Snowflake から ServiceNow への HTTPS 通信を許可するルール
-- -----------------------------------------------------------------------------
CREATE NETWORK RULE CONNECTORS_SECRET.SERVICENOW.SERVICENOW_NETWORK_RULE
  MODE = 'EGRESS'
  TYPE = 'HOST_PORT'
  VALUE_LIST = ('<your-instance>.service-now.com');

-- -----------------------------------------------------------------------------
-- Step 3.5: External Access Integration 作成
-- ネットワークルールと認証情報を紐付け、Connector が外部通信できるようにする
-- -----------------------------------------------------------------------------
CREATE EXTERNAL ACCESS INTEGRATION SERVICENOW_EAI
  ALLOWED_NETWORK_RULES = (CONNECTORS_SECRET.SERVICENOW.SERVICENOW_NETWORK_RULE)
  ALLOWED_AUTHENTICATION_SECRETS = (CONNECTORS_SECRET.SERVICENOW.SERVICENOW_CREDS)
  ENABLED = TRUE;

-- -----------------------------------------------------------------------------
-- Step 3.6: Connector アプリケーションへの権限付与
-- Connector がタスク実行、ウェアハウス利用、データ書き込み、認証情報読み取りを行うための権限
-- -----------------------------------------------------------------------------
GRANT EXECUTE TASK ON ACCOUNT TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON DATABASE SERVICENOW_DEST_DB TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT USAGE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT CREATE TABLE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT CREATE VIEW ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON INTEGRATION SERVICENOW_EAI TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON DATABASE CONNECTORS_SECRET TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT USAGE ON SCHEMA CONNECTORS_SECRET.SERVICENOW TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT READ ON SECRET CONNECTORS_SECRET.SERVICENOW.SERVICENOW_CREDS TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT USAGE ON SECRET CONNECTORS_SECRET.SERVICENOW.SERVICENOW_CREDS TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

-- -----------------------------------------------------------------------------
-- Step 5.2: 同期データの行数確認
-- Connector の UI ウィザード設定（Step 4）完了後に実行
-- -----------------------------------------------------------------------------
SELECT 'INCIDENT' AS table_name, COUNT(*) AS row_count FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
UNION ALL
SELECT 'SYS_USER', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER
UNION ALL
SELECT 'SYS_USER_GROUP', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP
UNION ALL
SELECT 'TASK_SLA', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA;

-- -----------------------------------------------------------------------------
-- Step 5.3: インシデントデータのサンプル確認
-- -----------------------------------------------------------------------------
SELECT
    NUMBER,
    SHORT_DESCRIPTION,
    PRIORITY,
    STATE,
    CATEGORY,
    ASSIGNED_TO,
    SYS_CREATED_ON,
    CLOSED_AT
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
LIMIT 10;
