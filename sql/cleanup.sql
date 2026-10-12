-- =============================================================================
-- クリーンアップ: ハンズオンで作成したオブジェクトの削除
-- =============================================================================
-- ハンズオン終了後 or 再実行前にリソースを削除します。
--
-- 【重要】Connector はアンインストールしません。
-- 同じ Connector インスタンスを維持することで、DEST_SCHEMA を再利用できます。
-- Connector をアンインストールすると、スキーマ名が platform レベルでブロックされ、
-- 同じ名前での再登録ができなくなります。
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 1: Streamlit アプリの削除
-- -----------------------------------------------------------------------------
DROP STREAMLIT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP;
REMOVE @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- -----------------------------------------------------------------------------
-- Step 2: Cortex Agent の削除
-- -----------------------------------------------------------------------------
DROP AGENT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT;

-- -----------------------------------------------------------------------------
-- Step 3: Cortex Search Service の削除
-- -----------------------------------------------------------------------------
DROP CORTEX SEARCH SERVICE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE;
DROP VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.V_INCIDENT_SEARCH;

-- -----------------------------------------------------------------------------
-- Step 4: Semantic View の削除
-- -----------------------------------------------------------------------------
DROP SEMANTIC VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;

-- -----------------------------------------------------------------------------
-- Step 5: Dynamic Tables の削除
-- -----------------------------------------------------------------------------
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED;

-- -----------------------------------------------------------------------------
-- Step 6: S3 関連オブジェクトの削除
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE;
DROP STORAGE INTEGRATION IF EXISTS S3_HANDSON_INTEGRATION;

-- -----------------------------------------------------------------------------
-- Step 7: 分析用データベースの削除
-- -----------------------------------------------------------------------------
DROP DATABASE IF EXISTS SERVICENOW_HANDSON;

-- -----------------------------------------------------------------------------
-- Step 8: ウェアハウスサイズを元に戻す
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- -----------------------------------------------------------------------------
-- Step 9: クリーンアップ後の確認
-- -----------------------------------------------------------------------------
-- Connector 関連は残っていて正常:
--   - APPLICATION: SNOWFLAKE_CONNECTOR_FOR_SERVICENOW
--   - DATABASE: SERVICENOW_DEST_DB / CONNECTORS_SECRET
--   - SECURITY INTEGRATION: SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION
--   - EXTERNAL ACCESS INTEGRATION: SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION

SHOW DATABASES;
SHOW INTEGRATIONS;
SHOW APPLICATIONS;

-- =============================================================================
-- 【完全リセットが必要な場合】
-- Connector 自体もアンインストールする場合は、以下を順番に実行してください。
-- ※ 再インストール後に同じスキーマ名 (DEST_SCHEMA) は使えなくなります。
--
-- 1. Snowsight > Data Products > Connectors > Pause
-- 2. DROP APPLICATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW CASCADE;
-- 3. DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
-- 4. DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
-- 5. DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
-- 6. DROP DATABASE IF EXISTS CONNECTORS_SECRET;
-- 7. DROP DATABASE IF EXISTS SERVICENOW_DEST_DB;
-- =============================================================================
