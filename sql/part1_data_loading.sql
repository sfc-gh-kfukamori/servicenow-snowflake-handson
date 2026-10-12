-- =============================================================================
-- Part 1: ServiceNow Connector 設定 — Snowflake 側 SQL
-- =============================================================================
-- このスクリプトは ServiceNow Connector の Snowflake 側セットアップ SQL をまとめたものです。
-- ServiceNow 側の OAuth2 設定（Step 1〜2）は手順書（part1_data_loading.md）を参照してください。
--
-- 認証関連オブジェクト（Security Integration、Secret、Network Rule、External Access Integration）
-- は Connector ウィザードの Authentication ステップで自動作成されるため、
-- ここでは同期先オブジェクトの作成と権限付与のみを行います。
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 3.1: ハンズオン用オブジェクトの作成
-- Connector のデータ保存先データベース・スキーマを作成
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.SERVICENOW_DATA;

-- -----------------------------------------------------------------------------
-- Step 3.2: Connector アプリケーションへの権限付与
-- Connector がタスク実行、ウェアハウス利用、同期先へのテーブル・ビュー作成を行うための権限
-- -----------------------------------------------------------------------------
GRANT EXECUTE TASK ON ACCOUNT TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON DATABASE SERVICENOW_DEST_DB TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT USAGE ON SCHEMA SERVICENOW_DEST_DB.SERVICENOW_DATA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT CREATE TABLE ON SCHEMA SERVICENOW_DEST_DB.SERVICENOW_DATA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT CREATE VIEW ON SCHEMA SERVICENOW_DEST_DB.SERVICENOW_DATA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

-- 同期先スキーマの所有権を Connector に移譲（再セットアップ時のスキーマ競合を防止）
CALL system$grant_ownership_to_application('SNOWFLAKE_CONNECTOR_FOR_SERVICENOW', true, 'SERVICENOW_DEST_DB', 'SERVICENOW_DATA');

-- -----------------------------------------------------------------------------
-- Step 5.2: 同期データの行数確認
-- Connector の UI ウィザード設定（Step 4）完了後に実行
-- -----------------------------------------------------------------------------
SELECT 'INCIDENT' AS table_name, COUNT(*) AS row_count FROM SERVICENOW_DEST_DB.SERVICENOW_DATA.INCIDENT
UNION ALL
SELECT 'SYS_USER', COUNT(*) FROM SERVICENOW_DEST_DB.SERVICENOW_DATA.SYS_USER
UNION ALL
SELECT 'SYS_USER_GROUP', COUNT(*) FROM SERVICENOW_DEST_DB.SERVICENOW_DATA.SYS_USER_GROUP
UNION ALL
SELECT 'TASK_SLA', COUNT(*) FROM SERVICENOW_DEST_DB.SERVICENOW_DATA.TASK_SLA;

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
FROM SERVICENOW_DEST_DB.SERVICENOW_DATA.INCIDENT
LIMIT 10;
