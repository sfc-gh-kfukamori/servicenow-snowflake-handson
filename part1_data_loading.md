# Part 1: ServiceNow Connector Setup and Data Loading

## Overview

In this part, you will set up a ServiceNow Personal Developer Instance (PDI) and securely sync data using the Snowflake Connector for ServiceNow with **OAuth2 Client Credentials** authentication.

## Prerequisites

- Snowflake account (ACCOUNTADMIN role)
- Snowflake Connector for ServiceNow installed (available from **Data Products → Connectors** in Snowsight)

---

## Step 1: Creating a ServiceNow Personal Developer Instance (PDI)

### 1.1 Registering for the ServiceNow Developer Program

1. Go to the [ServiceNow Developer site](https://developer.servicenow.com/)
2. Click **Sign up** and create an account (enter your email address, password, etc.)
3. Complete email verification and log in

### 1.2 Creating a PDI (Personal Developer Instance)

1. After logging in, click **Request Instance** from the dashboard
2. Select the instance type (latest release recommended)
3. The instance will be created in a few minutes and the following information will be displayed:
   - **Instance URL**: `https://<your-instance>.service-now.com`
   - **Username**: `admin`
   - **Password**: Shown on the Instance management page of the dashboard

> **Note**: If you are logged into the PDI via SSO, you can check the `admin` password on the developer.servicenow.com dashboard. You can also reset the password from the "Manage instance password" link.

### 1.3 Verifying Demo Data in the PDI

The PDI comes preloaded with ITSM (IT Service Management) demo data. The following tables will be used in this hands-on:

| Table | Description | Approximate Count |
|---|---|---|
| `incident` | Incidents (fault reports) | Several dozen |
| `sys_user` | System users | Several hundred |
| `sys_user_group` | User groups | Several dozen |
| `task_sla` | Task SLA achievement status | Several dozen |

---

## Step 2: OAuth2 Configuration on the ServiceNow Side

With production environments in mind, we will configure **OAuth2 Client Credentials** authentication. Using OAuth2 instead of Basic authentication (ID/password) meets security requirements.

### 2.1 Enabling the Client Credentials Grant Type

In ServiceNow, the Client Credentials Grant Type is disabled by default, so you need to create a system property to enable it.

1. Enter the following URL directly in your browser's address bar:
   ```
   https://<your-instance>.service-now.com/sys_properties_list.do?sysparm_query=name=glide.oauth.inbound.client.credential.grant_type.enabled
   ```

2. If "No records to display" is shown, click the **New** button in the upper right

3. Enter the following and click **Submit**:
   - **Name**: `glide.oauth.inbound.client.credential.grant_type.enabled`
   - **Type**: `true | false`
   - **Value**: `true`

> **Note**: In the ServiceNow Next Experience UI (Polaris), searching for `sys_properties` in the navigation filter will not return results. Please access it by entering the URL directly.

### 2.2 Creating an OAuth Application

1. Enter the following URL directly in your browser's address bar:
   ```
   https://<your-instance>.service-now.com/oauth_entity_list.do
   ```

2. Click **New**

3. Enter the following:
   - **Name**: `Snowflake Connector` (any name of your choice)
   - **Accessible from**: `All application scopes`
   - **Active**: Checked

4. Click **Submit**

5. Reopen the created record and note down the auto-generated **Client ID** and **Client Secret**

> **Important**: The Client Secret may only be displayed once. Make sure to note it down at this point.

### 2.3 Configuring the OAuth Application User

This configures which user will be used to access the API when authenticating with OAuth2 Client Credentials.

1. Open the "Snowflake Connector" record you created earlier

2. If the **OAuth Application User** field is not displayed:
   - Open the hamburger menu (≡) in the upper left → **Configure → Form Builder**
   - Search for `OAuth Application User` in the field list on the left
   - Drag and drop it onto the form and click **Save** in the upper right
   - Close Form Builder and return to the record screen

3. Click the magnifying glass icon on the **OAuth Application User** field and select **System Administrator** (admin)

4. Change **Scope Restriction** to **Broadly scoped**

5. Click **Update**

> **Note**: If Scope Restriction remains set to `Securely scoped`, you will get an `Access to unscoped api is not allowed` error. Make sure to change it to `Broadly scoped`.

---

## Step 3: Preparation on the Snowflake Side

Execute the following in a Snowsight SQL worksheet.

### 3.1 Creating Objects for the Hands-on

```sql
-- =============================================
-- Step 3.1: Creating objects for the hands-on
-- =============================================
USE ROLE ACCOUNTADMIN;

-- Create the destination database and schema for the Connector
CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
```

> **Important**: Do not execute the GRANT statements or `system$grant_ownership_to_application` after this. All permission grants will be performed automatically by the wizard. Running GRANT statements in advance will cause a "Selected schema is in use by the other connector instance" error.

> **Explanation**: You only need to create the database and schema. All permission grants (GRANT), authentication objects (Security Integration, Secret, Network Rule, External Access Integration) are automatically created and configured by the wizard.



---

## Step 4: Connector Configuration (UI Wizard)

Use the Snowsight UI wizard to configure the Connector.

### 4.1 Opening the Wizard

1. In Snowsight, navigate to **Data Products → Connectors**
2. Click **Snowflake Connector for ServiceNow**
3. Open the **Wizard** tab

### 4.2 Prerequisites

Follow the on-screen instructions to verify the warehouse and destination database/schema, then proceed to the next step.

### 4.3 Configure

- **Warehouse**: `COMPUTE_WH`
- **Destination Database**: `SERVICENOW_DEST_DB`
- **Destination Schema**: Select "**Select existing**" and choose `DEST_SCHEMA`
- **Role**: `ACCOUNTADMIN` (select from Select existing)

### 4.4 Authentication

1. Select **OAuth2 Client Credentials [Recommended]** as the authentication method
2. Enter the following:
   - **ServiceNow Instance**: `<your-instance>` (only the `dev12345` portion)
   - **Client ID**: The Client ID you noted in Step 2.2
   - **Client Secret**: The Client Secret you noted in Step 2.2
3. Click **Connect**

> **Troubleshooting**: If you get an `access_denied` error, re-check the system property creation in Step 2.1 and the Scope Restriction setting in Step 2.3.

### 4.5 Validate source

- `sys_audit_delete` will appear in the **Journal Table** field, so click **Validate** as is

---

## Step 5: Starting Table Synchronization

### 5.1 Selecting Tables to Sync

Once validation succeeds, you will proceed to the table selection screen.

1. Click **Edit tables**
2. Search for and add the following 4 tables:
   - `incident`
   - `sys_user`
   - `sys_user_group`
   - `task_sla`
3. Leave **Sync Every** at the default `1 hour`
4. Enable the tables

> **Explanation**: The PDI comes with demo data preloaded in these tables. This provides the data needed for incident management, user management, and SLA tracking.

### 5.2 Verifying Sync Completion

Once synchronization starts, the status of each table will display as "Syncing data". The initial sync completes in a few minutes.

```sql
-- =============================================
-- Step 5.2: Checking row counts of synced data
-- =============================================
SELECT 'INCIDENT' AS table_name, COUNT(*) AS row_count FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
UNION ALL
SELECT 'SYS_USER', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER
UNION ALL
SELECT 'SYS_USER_GROUP', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP
UNION ALL
SELECT 'TASK_SLA', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA;
```

Expected results (may vary slightly depending on the amount of demo data in the PDI):

| Table | Approximate Count |
|---|---|
| INCIDENT | 60–70 rows |
| SYS_USER | 600–650 rows |
| SYS_USER_GROUP | 50–55 rows |
| TASK_SLA | 10–20 rows |

### 5.3 Checking Raw Data Synced by the Connector

```sql
-- =============================================
-- Step 5.3: Checking raw data (RAW column)
-- =============================================
SELECT * FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT LIMIT 5;
```

> **Explanation**: Tables synced by the Connector consist of columns such as `SYS_ID`, `RAW` (VARIANT type), and `IS_DELETED`. The `RAW` column stores all ServiceNow fields in JSON format.

### 5.4 Expanding the RAW Column to Inspect Data

```sql
-- =============================================
-- Step 5.3: Checking incident data
-- =============================================
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
```

> **Explanation**: The Connector creates the following for each ServiceNow table:
> - `<TABLE_NAME>`: Data table
> - `<TABLE_NAME>__EVENT_LOG`: Change history table

---

## Step 6: (Reference) Pausing the Connector

After completing all parts of the hands-on, pause the Connector to prevent unnecessary credit consumption.

Open **Data Products → Connectors → Snowflake Connector for ServiceNow** in Snowsight and click the **Pause Connector** button on the **Data Sync** tab.

> **Note**: If you do not stop the Connector, the warehouse will start every hour and consume credits. Make sure to stop it after the hands-on is complete.

---

## Summary

What was accomplished in this part:

1. Created a ServiceNow PDI (Personal Developer Instance)
2. Configured OAuth2 Client Credentials on the ServiceNow side (system property, OAuth application, Application User, Scope Restriction)
3. Created the destination database and schema on the Snowflake side and granted permissions to the Connector
4. Configured the Connector using the UI wizard and connected with OAuth2 Client Credentials
5. Started and verified synchronization of 4 tables (incident, sys_user, sys_user_group, task_sla)

**Next Part**: Proceed to [Part 2: Data Transformation with Dynamic Tables](part2_dynamic_tables.md).
