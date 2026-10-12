-- =============================================================================
-- クリーンアップ: ハンズオンで作成した全オブジェクトの完全削除
-- =============================================================================
-- ハンズオン終了後 or 再実行前に全リソースを削除します。
-- Connector も含めて完全にアンインストールし、一からやり直せる状態にします。
--
-- 【再インストール時に同じスキーマ (DEST_SCHEMA) を再利用する手順】
-- 公式ドキュメント準拠:
--   1. アンインストール前にオーナーシップをアカウントロールに移管
--   2. Connector をアンインストール（同期先データは残す）
--   3. 再インストール時にウィザードで同じスキーマを選択
--   4. finalize 前に system$grant_ownership_to_application を実行
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
-- Phase 2: Connector のアンインストール（同じスキーマを再利用可能にする手順）
-- =============================================================================

-- Step 9: オーナーシップをアカウントロールに移管
-- ※ アンインストール前に実行すること。これにより同期先テーブル・ビューが保持される。
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA
  TO ROLE ACCOUNTADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL VIEWS IN SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA
  TO ROLE ACCOUNTADMIN COPY CURRENT GRANTS;

-- Step 10: Connector アプリのアンインストール
-- Snowsight > Data Products > Connectors で Pause してから実行
DROP APPLICATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW CASCADE;

-- Step 11: Connector が自動作成した認証オブジェクトの削除
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
DROP DATABASE IF EXISTS CONNECTORS_SECRET;

-- Step 12: 同期先データの削除
-- ※ データを保持して再利用する場合は、このステップをスキップ
DROP SCHEMA IF EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
DROP DATABASE IF EXISTS SERVICENOW_DEST_DB;

-- =============================================================================
-- Phase 3: クリーンアップ確認
-- =============================================================================
SHOW DATABASES;
SHOW INTEGRATIONS;
SHOW APPLICATIONS;

-- =============================================================================
-- 【再セットアップ手順】
-- 1. Part 1 の手順に従い DB/Schema を作成:
--      CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
--      CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
--
-- 2. Snowsight > Data Products > Connectors から再インストール
--    - ウィザードで Role = ACCOUNTADMIN を指定
--    - Destination DB = SERVICENOW_DEST_DB, Schema = DEST_SCHEMA を選択
--
-- 3. ウィザードの Configure 画面が出たら、finalize 前に以下を実行:
--      GRANT USAGE ON DATABASE SERVICENOW_DEST_DB
--        TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
--      GRANT USAGE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA
--        TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
--      GRANT CREATE TABLE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA
--        TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
--      GRANT CREATE VIEW ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA
--        TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
--      CALL system$grant_ownership_to_application(
--        'SNOWFLAKE_CONNECTOR_FOR_SERVICENOW', true,
--        'SERVICENOW_DEST_DB', 'DEST_SCHEMA');
--
-- 4. ウィザードで Authentication を設定して finalize
--
-- ※「Selected schema is in use by the other connector instance」エラーが出た場合:
--    上記 Step 3 の system$grant_ownership_to_application を実行してからリトライ
-- =============================================================================
