-- =============================================================================
-- Part 1: ServiceNow Connector 設定 — Snowflake 側 SQL
-- =============================================================================
-- このスクリプトは ServiceNow Connector の Snowflake 側セットアップ SQL をまとめたものです。
-- ServiceNow 側の OAuth2 設定（Step 1〜2）は手順書（part1_data_loading.md）を参照してください。
--
-- 【重要】権限付与（GRANT）やスキーマ関連の設定は全てウィザードが自動で行います。
-- 事前に GRANT 文や system$grant_ownership_to_application を実行すると
-- 「Selected schema is in use by the other connector instance」エラーが発生します。
-- ここではデータベース・スキーマの作成のみを行います。
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 3.1: ハンズオン用オブジェクトの作成
-- Connector のデータ保存先データベース・スキーマを作成
-- ※ ウィザードの Configure 画面で「Select existing」を選んで使用する
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;

-- この後は手順書（part1_data_loading.md）の Step 4 に従い、
-- Snowsight の UI ウィザードで Connector を設定してください。
-- 権限付与・認証オブジェクト作成は全てウィザードが自動で行います。

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
