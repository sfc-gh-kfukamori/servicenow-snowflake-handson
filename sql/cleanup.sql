-- =============================================================================
-- Cleanup: Delete objects created during the hands-on lab
-- =============================================================================
-- Cleanup steps for re-running the hands-on lab on the same account.
--
-- [IMPORTANT]
-- - The Connector is NOT uninstalled (uninstalling permanently blocks the
--   schema name).
-- - GRANT statements and system$grant_ownership_to_application are NOT executed
--   (pre-granting permissions causes a "schema is in use" error in the wizard).
-- - The destination schema is DROPped and re-CREATEd, then reconfigured
--   via the wizard.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Phase 1: Delete objects created in hands-on Parts 2-5
-- =============================================================================

-- Step 1: Delete the Streamlit app
DROP STREAMLIT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP;
REMOVE @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- Step 2: Delete the Cortex Agent
DROP AGENT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT;

-- Step 3: Delete the Cortex Search Service
DROP CORTEX SEARCH SERVICE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE;
DROP VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.V_INCIDENT_SEARCH;

-- Step 4: Delete the Semantic View
DROP SEMANTIC VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;

-- Step 5: Delete Dynamic Tables
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED;

-- Step 6: Delete S3-related objects
DROP TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE;
DROP STORAGE INTEGRATION IF EXISTS S3_HANDSON_INTEGRATION;

-- Step 7: Delete the analytics database
DROP DATABASE IF EXISTS SERVICENOW_HANDSON;

-- Step 8: Reset warehouse size
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- =============================================================================
-- Phase 2: Reset destination schema (Connector is NOT uninstalled)
-- =============================================================================

-- Step 9: DROP and re-CREATE the destination schema
DROP SCHEMA IF EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
CREATE SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA;

-- Step 10: Delete authentication objects auto-created by the Connector
-- New objects will be auto-created when reconfigured via the wizard
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
DROP DATABASE IF EXISTS CONNECTORS_SECRET;

-- * Do NOT execute GRANT statements or system$grant_ownership_to_application.
--   The wizard handles all permission grants automatically.
--   Running GRANT in advance causes a "schema is in use" error.

-- =============================================================================
-- Phase 3: Cleanup verification
-- =============================================================================
SHOW DATABASES;
SHOW INTEGRATIONS;
SHOW APPLICATIONS;

-- Expected results:
--   DATABASES: SERVICENOW_DEST_DB remains (normal)
--   APPLICATIONS: SNOWFLAKE_CONNECTOR_FOR_SERVICENOW remains (normal)
--   INTEGRATIONS: Connector authentication objects have been deleted

-- =============================================================================
-- [Re-setup steps]
-- 1. Open Snowsight > Data Products > Connectors
-- 2. Reconfigure in the SNOWFLAKE_CONNECTOR_FOR_SERVICENOW Configure screen
--    - Warehouse: COMPUTE_WH
--    - Destination DB: SERVICENOW_DEST_DB
--    - Destination Schema: DEST_SCHEMA (Select existing)
--    - Role: ACCOUNTADMIN
-- 3. Re-enter ServiceNow credentials in Authentication
-- 4. Validate -> Resume table sync
--
-- * Do NOT execute GRANT statements. The wizard handles all permissions
--   automatically.
-- =============================================================================

-- =============================================================================
-- [Full reset (not recommended)]
-- If you also want to uninstall the Connector itself, execute the following.
-- * Warning: After reinstalling, the same schema name (DEST_SCHEMA) can no
--            longer be used. A new schema name will be required next time.
--
-- DROP APPLICATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW CASCADE;
-- DROP EXTERNAL ACCESS INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_EXTERNAL_ACCESS_INTEGRATION;
-- DROP SECURITY INTEGRATION IF EXISTS SNOWFLAKE_CONNECTOR_FOR_SERVICENOW_SECURITY_INTEGRATION;
-- DROP SCHEMA IF EXISTS CONNECTORS_SECRET.SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
-- DROP DATABASE IF EXISTS CONNECTORS_SECRET;
-- DROP DATABASE IF EXISTS SERVICENOW_DEST_DB;
-- =============================================================================
