-- =============================================================================
-- クリーンアップ: ハンズオンで作成した全オブジェクトの削除
-- =============================================================================
-- ハンズオン終了後にリソースを削除してクレジット消費を停止します。
-- 必要に応じて選択的に実行してください。
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 1: Streamlit アプリの削除
-- -----------------------------------------------------------------------------
DROP STREAMLIT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP;

-- ステージのクリーンアップ
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
-- Step 8: Connector 関連オブジェクトの削除
-- Connector の停止: Snowsight > Data Products > Connectors > Pause Connector
-- Connector アプリのアンインストール: Snowsight > Data Products > Connectors > アンインストール
-- Connector が自動作成したオブジェクトも含めて全て削除
-- -----------------------------------------------------------------------------
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SERVICENOW_EAI;
DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
DROP SECURITY INTEGRATION IF EXISTS SERVICENOW_OAUTH2;
DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SERVICENOW;
DROP DATABASE IF EXISTS CONNECTORS_SECRET;
DROP SCHEMA IF EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
DROP DATABASE IF EXISTS SERVICENOW_DEST_DB;

-- -----------------------------------------------------------------------------
-- Step 9: ウェアハウスサイズを元に戻す
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- -----------------------------------------------------------------------------
-- Step 10: クリーンアップ後の確認
-- 以下を実行して、ハンズオン関連のオブジェクトが残っていないことを確認
-- -----------------------------------------------------------------------------
SHOW DATABASES;
SHOW INTEGRATIONS;
SHOW APPLICATIONS;
