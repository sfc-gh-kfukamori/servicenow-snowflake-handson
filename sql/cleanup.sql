-- =============================================================================
-- クリーンアップ: ハンズオンで作成したオブジェクトの削除
-- =============================================================================
-- 同じアカウントでハンズオンを再実行するためのクリーンアップ手順です。
--
-- 【重要】
-- - Connector はアンインストールしません（アンインストールするとスキーマ名が
--   永久にブロックされるため）。
-- - GRANT 文や system$grant_ownership_to_application は実行しません
--  （事前に権限付与するとウィザードで「schema is in use」エラーが発生するため）。
-- - 同期先スキーマを DROP → CREATE し直し、ウィザードで再設定します。
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Phase 1: ハンズオン Part 2〜5 で作成したオブジェクトの削除
-- =============================================================================

-- Step 1: Streamlit アプリの削除
DROP STREAMLIT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP;
REMOVE @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- Step 2: Cortex Agent の削除
DROP AGENT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT;

-- Step 3: Cortex Search Service の削除
DROP CORTEX SEARCH SERVICE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE;
DROP VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.V_INCIDENT_SEARCH;

-- Step 4: Semantic View の削除
DROP SEMANTIC VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;

-- Step 5: Dynamic Tables の削除
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED;

-- Step 6: S3 関連オブジェクトの削除
DROP TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE;
DROP STORAGE INTEGRATION IF EXISTS S3_HANDSON_INTEGRATION;

-- Step 7: 分析用データベースの削除
DROP DATABASE IF EXISTS SERVICENOW_HANDSON;

-- Step 8: ウェアハウスサイズを元に戻す
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- =============================================================================
-- Phase 2: 同期先スキーマのリセット（Connector はアンインストールしない）
-- =============================================================================

-- Step 9: 同期先スキーマを DROP して再作成
DROP SCHEMA IF EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
CREATE SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA;

-- Step 10: Connector が自動作成した認証オブジェクトの削除
-- ウィザードで再設定時に新しいオブジェクトが自動作成される
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
DROP DATABASE IF EXISTS CONNECTORS_SECRET;

-- ※ GRANT 文や system$grant_ownership_to_application は実行しないこと。
--   権限付与はウィザードが全て自動で行う。
--   事前に GRANT を実行すると「schema is in use」エラーが発生する。

-- =============================================================================
-- Phase 3: クリーンアップ確認
-- =============================================================================
SHOW DATABASES;
SHOW INTEGRATIONS;
SHOW APPLICATIONS;

-- 期待される結果:
--   DATABASES: SERVICENOW_DEST_DB が残っている（正常）
--   APPLICATIONS: SNOWFLAKE_CONNECTOR_FOR_SERVICENOW が残っている（正常）
--   INTEGRATIONS: Connector の認証オブジェクトは削除済み

-- =============================================================================
-- 【再セットアップ手順】
-- 1. Snowsight > Data Products > Connectors を開く
-- 2. SNOWFLAKE_CONNECTOR_FOR_SERVICENOW の Configure 画面で再設定
--    - Warehouse: COMPUTE_WH
--    - Destination DB: SERVICENOW_DEST_DB
--    - Destination Schema: DEST_SCHEMA（Select existing）
--    - Role: ACCOUNTADMIN
-- 3. Authentication で ServiceNow 認証情報を再入力
-- 4. Validate → テーブル同期を再開
--
-- ※ GRANT 文は実行しない。ウィザードが全て自動で権限設定する。
-- =============================================================================

-- =============================================================================
-- 【完全リセット（非推奨）】
-- Connector 自体もアンインストールする場合は以下を実行。
-- ※ 警告: 再インストール後に同じスキーマ名 (DEST_SCHEMA) は使えなくなります。
--          次回は新しいスキーマ名が必要です。
--
-- DROP APPLICATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW CASCADE;
-- DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
-- DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
-- DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
-- DROP DATABASE IF EXISTS CONNECTORS_SECRET;
-- DROP DATABASE IF EXISTS SERVICENOW_DEST_DB;
-- =============================================================================
