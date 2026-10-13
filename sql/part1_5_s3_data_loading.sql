-- =============================================================================
-- Part 1.5: Data Loading from AWS S3 (External Data Integration)
-- =============================================================================
-- Load IT infrastructure event logs (50 million rows, 10 files) from S3 into
-- Snowflake, and experience the performance difference based on warehouse size.
--
-- AWS integration info:
--   AWS Account ID  : 484577546576
--   IAM Role        : oist-handson-snowflake-s3-role
--   S3 Bucket       : s3://oist-handson/handson/ (ap-northeast-1)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- -----------------------------------------------------------------------------
-- Step 1: Create the event log table
-- Target table for data loaded from S3
-- Columns: event ID, timestamp, server name, event type, severity, category,
--          description, source IP
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE IT_EVENT_LOGS (
    event_id        STRING,
    timestamp       TIMESTAMP_NTZ,
    server_name     STRING,
    event_type      STRING,      -- INFO, WARNING, ERROR, CRITICAL
    severity        INT,         -- 1=CRITICAL, 2=ERROR, 3=WARNING, 4=INFO
    category        STRING,      -- network, software, hardware, inquiry, database
    description     STRING,
    source_ip       STRING
);

-- -----------------------------------------------------------------------------
-- Step 2: Create the Storage Integration
-- Configuration for Snowflake to access the S3 bucket using an AWS IAM role.
-- After creation, the IAM_USER_ARN and EXTERNAL_ID shown by DESC INTEGRATION
-- must be set in the AWS IAM role trust policy (pre-configured by the
-- instructor).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE STORAGE INTEGRATION s3_handson_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::484577546576:role/oist-handson-snowflake-s3-role'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('s3://oist-handson/handson/');

-- Verify Snowflake-side info (needed for the AWS IAM trust policy)
DESC INTEGRATION s3_handson_integration;

-- -----------------------------------------------------------------------------
-- Step 3: Create the External Stage
-- Mount the S3 bucket as a Snowflake stage using the Storage Integration.
-- FILE_FORMAT specifies CSV format, GZIP compression, and header skip.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE STAGE S3_EVENT_STAGE
  STORAGE_INTEGRATION = s3_handson_integration
  URL = 's3://oist-handson/handson/'
  FILE_FORMAT = (
    TYPE = CSV
    COMPRESSION = GZIP
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  );

-- Verify the file listing on S3 (10 files should be displayed)
LIST @S3_EVENT_STAGE;

-- -----------------------------------------------------------------------------
-- Step 4.1: Load with XS (X-Small) warehouse
-- First, measure load time using the smallest warehouse size.
-- SUSPEND -> RESUME to clear the warehouse cache for a fair comparison.
-- Reference: approx. 30 seconds
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

COPY INTO IT_EVENT_LOGS
  FROM @S3_EVENT_STAGE
  -- PATTERN = '.*it_event_logs_[0-9]+\.csv\.gz'
  ;

-- Record the load time from Query History

-- Verify load results
SELECT COUNT(*) AS row_count FROM IT_EVENT_LOGS;
SELECT * FROM IT_EVENT_LOGS LIMIT 5;

-- -----------------------------------------------------------------------------
-- Step 4.2: Clear the table to prepare for reload
-- -----------------------------------------------------------------------------
TRUNCATE TABLE IT_EVENT_LOGS;

-- Verify table is cleared
SELECT * FROM IT_EVENT_LOGS;

-- -----------------------------------------------------------------------------
-- Step 4.3: Load with M (Medium) warehouse
-- Increase the warehouse size and load the same data to compare performance.
-- Reference: approx. 14 seconds (about 2x faster than XS)
-- Medium uses 4 nodes to process 10 files in parallel, making it faster
-- than XS (1 node).
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'MEDIUM';

show warehouses in account;

ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

COPY INTO IT_EVENT_LOGS
  FROM @S3_EVENT_STAGE
 // PATTERN = '.*it_event_logs_[0-9]+\.csv\.gz'
 ;

-- Record the load time from Query History

-- -----------------------------------------------------------------------------
-- Step 4.4: Reset warehouse size (cost saving)
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- -----------------------------------------------------------------------------
-- Step 5: Verify loaded data
-- -----------------------------------------------------------------------------

-- Row count check (expected: 50 million rows)
SELECT COUNT(*) AS total_rows FROM IT_EVENT_LOGS;

-- Sample data
SELECT * FROM IT_EVENT_LOGS LIMIT 10;

-- Aggregation by category
SELECT
    category,
    COUNT(*) AS event_count,
    COUNT(CASE WHEN event_type = 'CRITICAL' THEN 1 END) AS critical_count,
    MIN(timestamp) AS earliest,
    MAX(timestamp) AS latest
FROM IT_EVENT_LOGS
GROUP BY category
ORDER BY event_count DESC;

-- -----------------------------------------------------------------------------
-- Step 6: Dynamic Table for event log x incident correlation analysis
-- Correlate event logs and incidents by category + date for correlation analysis.
-- Analyze: "Are incidents higher on days with many events?" and
-- "Is there correlation with CRITICAL events?"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE DT_EVENT_INCIDENT_CORRELATION
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    DATE_TRUNC('day', e.timestamp)::DATE AS event_date,
    e.category,
    COUNT(DISTINCT e.event_id) AS event_count,
    COUNT(DISTINCT CASE WHEN e.event_type = 'CRITICAL' THEN e.event_id END) AS critical_event_count,
    COUNT(DISTINCT CASE WHEN e.event_type = 'ERROR' THEN e.event_id END) AS error_event_count,
    COUNT(DISTINCT i.sys_id) AS incident_count,
    ROUND(AVG(i.mttr_hours), 2) AS avg_mttr_hours
FROM IT_EVENT_LOGS e
LEFT JOIN DT_INCIDENT_ENRICHED i
    ON e.category = i.category
    AND DATE_TRUNC('day', e.timestamp) = DATE_TRUNC('day', i.opened_at)
GROUP BY 1, 2;

-- List and check status of Dynamic Tables
SHOW DYNAMIC TABLES IN SCHEMA SERVICENOW_HANDSON.ANALYTICS;

ALTER DYNAMIC TABLE DT_EVENT_INCIDENT_CORRELATION REFRESH;

SELECT * FROM DT_EVENT_INCIDENT_CORRELATION
ORDER BY incident_count DESC;
