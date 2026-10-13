-- =============================================================================
-- Part 1: ServiceNow Connector Setup — Snowflake-side SQL
-- =============================================================================
-- This script contains the Snowflake-side setup SQL for the ServiceNow Connector.
-- For the ServiceNow-side OAuth2 configuration (Steps 1-2), refer to the
-- guide (part1_data_loading.md).
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Step 3.1: Create objects for the hands-on lab
-- Create the database and schema where the Connector stores its data
-- * Select "Select existing" in the wizard's Configure screen
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;

-- Next, follow Step 4 in the guide (part1_data_loading.md) to configure
-- the Connector via the Snowsight UI wizard.
-- The wizard handles all permission grants and authentication object creation
-- automatically.

-- -----------------------------------------------------------------------------
-- Step 5.2: Verify synced data row counts
-- Execute after completing the Connector UI wizard setup (Step 4)
-- -----------------------------------------------------------------------------
SELECT 'INCIDENT' AS table_name, COUNT(*) AS row_count FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
UNION ALL
SELECT 'SYS_USER', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER
UNION ALL
SELECT 'SYS_USER_GROUP', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP
UNION ALL
SELECT 'TASK_SLA', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA;

-- -----------------------------------------------------------------------------
-- Step 5.3: Inspect raw data synced by the Connector
-- All fields are stored in JSON format in the RAW column (VARIANT type)
-- -----------------------------------------------------------------------------
SELECT * FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT LIMIT 5;
SELECT * FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER LIMIT 5;
SELECT * FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP LIMIT 5;
SELECT * FROM SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA LIMIT 5;

-- -----------------------------------------------------------------------------
-- Step 5.4: Expand the RAW column to inspect incident data
-- Use the RAW:field::TYPE syntax to extract required fields
-- -----------------------------------------------------------------------------

SELECT * FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT LIMIT 5;

SELECT
    RAW:number::STRING AS number,
    RAW:short_description::STRING AS short_description,
    RAW:priority::STRING AS priority,
    RAW:state::STRING AS state,
    RAW:category::STRING AS category,
    RAW:assigned_to:value::STRING AS assigned_to,
    RAW:sys_created_on::STRING AS sys_created_on,
    RAW:closed_at::STRING AS closed_at
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
WHERE IS_DELETED = FALSE
LIMIT 10;
