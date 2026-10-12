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
-- -----------------------------------------------------------------------------
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SERVICENOW_EAI;
DROP SECRET IF EXISTS CONNECTORS_SECRET.SERVICENOW.SERVICENOW_CREDS;
DROP NETWORK RULE IF EXISTS CONNECTORS_SECRET.SERVICENOW.SERVICENOW_NETWORK_RULE;
DROP SECURITY INTEGRATION IF EXISTS SERVICENOW_OAUTH2;
DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SERVICENOW;
DROP DATABASE IF EXISTS CONNECTORS_SECRET;
DROP SCHEMA IF EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
DROP DATABASE IF EXISTS SERVICENOW_DEST_DB;

-- -----------------------------------------------------------------------------
-- Step 9: ウェアハウスサイズを元に戻す
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
