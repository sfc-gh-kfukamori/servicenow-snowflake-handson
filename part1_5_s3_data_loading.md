# Part 1.5: Data Loading from AWS S3 (External Data Integration)

## Overview

Load IT infrastructure event logs (50 million rows, approx. 2GB x 10 files) stored on AWS S3 into Snowflake. You will also experience the difference in load performance when changing warehouse sizes.

## Prerequisites

- Part 1 is completed, and ServiceNow data is synced
- The instructor has pre-placed event log files in the S3 bucket

## What You Will Learn in This Part

- Data loading from S3 using External Stage (COPY INTO)
- The relationship between warehouse size and load performance
- Cross-referencing analysis between external data and ServiceNow data

---

## Step 1: Create the Destination Table

```sql
-- =============================================
-- Step 1: Create event log table
-- =============================================
USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

CREATE OR REPLACE TABLE IT_EVENT_LOGS (
    event_id        STRING,
    timestamp       TIMESTAMP_NTZ,
    server_name     STRING,
    event_type      STRING,
    severity        INT,
    category        STRING,
    description     STRING,
    source_ip       STRING
);
```

---

## Step 2: Create the Storage Integration

Create a Storage Integration that authorizes Snowflake to access the S3 bucket.

```sql
-- =============================================
-- Step 2: Create Storage Integration
-- =============================================
CREATE OR REPLACE STORAGE INTEGRATION s3_handson_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::484577546576:role/oist-handson-snowflake-s3-role'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('s3://oist-handson/handson/');
```

### Setting the IAM Trust Policy (Pre-configured by the Instructor)

```sql
-- Check Snowflake-side information
DESC INTEGRATION s3_handson_integration;
```

Set the `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` from the output into the AWS IAM role's trust policy (pre-configured by the instructor).

---

## Step 3: Create the External Stage

```sql
-- =============================================
-- Step 3: Create External Stage
-- =============================================
CREATE OR REPLACE STAGE SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE
  STORAGE_INTEGRATION = s3_handson_integration
  URL = 's3://oist-handson/handson/'
  FILE_FORMAT = (
    TYPE = CSV
    COMPRESSION = GZIP
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  );
```

### Verify the Files

```sql
-- Check files on S3
LIST @SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE;
```

---

## Step 4: Performance Comparison by Warehouse Size

Experience how simply changing the warehouse size improves data loading performance.

### 4.1 Load with XS (X-Small) Warehouse

```sql
-- =============================================
-- Step 4.1: Load with XS warehouse
-- =============================================
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

-- Execute load (check the elapsed time)
COPY INTO SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
  FROM @SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE
  PATTERN = '.*it_event_logs_[0-9]+\\.csv\\.gz';
```

> **Check**: Record the load time from Query History. Reference value: approx. 30 seconds

```sql
-- Verify load results
SELECT COUNT(*) AS row_count FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
SELECT * FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS LIMIT 5;
```

### 4.2 Clear the Table and Prepare for Reload

```sql
-- Clear the table
TRUNCATE TABLE SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;

-- Verify cleared
SELECT * FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;
```

### 4.3 Load with M (Medium) Warehouse

```sql
-- =============================================
-- Step 4.3: Load with M warehouse
-- =============================================
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'MEDIUM';
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
ALTER WAREHOUSE COMPUTE_WH RESUME;

-- Execute load (check the elapsed time)
COPY INTO SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
  FROM @SERVICENOW_HANDSON.ANALYTICS.S3_EVENT_STAGE
  PATTERN = '.*it_event_logs_[0-9]+\\.csv\\.gz';
```

> **Check**: Record the load time from Query History. Reference value: approx. 14 seconds

### Performance Comparison Results (Reference Values)

| Warehouse Size | Execution Time | Rows |
|---|---|---|
| **X-Small** | Approx. 30 sec | 50,000,000 |
| **Medium** | Approx. 14 sec | 50,000,000 |

> **Key Point**: M is approximately 2x faster than XS. Snowflake loads 10 files in parallel, but XS processes them sequentially on a single node, whereas M processes them in parallel across multiple nodes, resulting in improved performance. No SQL changes or file splitting is required — just change the warehouse size.

### 4.4 Revert the Warehouse Size

```sql
-- Revert to XS to save costs
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL';
```

---

## Step 5: Verify the Loaded Data

```sql
-- =============================================
-- Step 5: Verify data
-- =============================================

-- Check row count
SELECT COUNT(*) AS total_rows FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS;

-- Sample data
SELECT * FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS LIMIT 10;

-- Aggregation by category
SELECT
    category,
    COUNT(*) AS event_count,
    COUNT(CASE WHEN event_type = 'CRITICAL' THEN 1 END) AS critical_count,
    MIN(timestamp) AS earliest,
    MAX(timestamp) AS latest
FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS
GROUP BY category
ORDER BY event_count DESC;
```

---

## Step 6: Dynamic Table for Event Log x Incident Cross-Referencing Analysis

```sql
-- =============================================
-- Step 6: Create Dynamic Table for cross-referencing analysis
-- =============================================
CREATE OR REPLACE DYNAMIC TABLE SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
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
FROM SERVICENOW_HANDSON.ANALYTICS.IT_EVENT_LOGS e
LEFT JOIN SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED i
    ON e.category = i.category
    AND DATE_TRUNC('day', e.timestamp) = DATE_TRUNC('day', i.opened_at)
GROUP BY 1, 2;
```

> **Explanation**:
> - Cross-references event logs and incidents by `category` and `date`
> - Enables analysis of questions like "Are there more incidents on days with many events?" and "What is the correlation between CRITICAL events and incidents?"

---

## Summary

What was accomplished in this part:

1. **S3 External Data Integration**: Secure access via Storage Integration + External Stage
2. **Bulk Loading with COPY INTO**: Loaded 50 million rows of event logs in parallel across 10 files
3. **Effect of Warehouse Sizing**: Demonstrated approx. 2x performance improvement from XS (approx. 30 sec) to M (approx. 14 sec)
4. **Cross-Referencing with External Data**: Created a Dynamic Table for correlation analysis between event logs and ServiceNow incidents

> **Key Point**: In Snowflake, performance improves simply by changing the warehouse size without modifying SQL. To handle increasing data volumes, you only need to change the warehouse "T-shirt size" instead of tuning infrastructure.

**Next Part**: Proceed to [Part 2: Data Transformation with Dynamic Tables](part2_dynamic_tables.md).
