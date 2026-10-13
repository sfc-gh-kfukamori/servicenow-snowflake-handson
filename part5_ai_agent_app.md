# Part 5: Building an AI Agent App (Cortex Agent + Streamlit)

## Overview

In this part, we build an AI agent that integrates the Semantic View (data analysis capability) created in Part 4 with full-text search of incident history, and provide a dashboard + chat UI via Streamlit in Snowflake.

## Prerequisites

- Part 4 is complete and the Semantic View has been created

## Architecture

```
┌───────────────────────────────────────────────────┐
│  Streamlit in Snowflake (IT_OPS_AGENT_APP)        │
│  ┌──────────────────┬──────────────────────────┐  │
│  │ Dashboard        │ AI Chat                  │  │
│  │ KPI Cards        │ Ask questions in          │  │
│  │ Monthly Trends   │ natural language          │  │
│  │ Category Analysis│ Agent responds            │  │
│  │ Team List        │ Processing steps shown    │  │
│  └──────────────────┴────────────┬─────────────┘  │
│                                  │                 │
│                                  ▼                 │
│            ┌─────────────────────────────┐         │
│            │     Cortex Agent            │         │
│            │  ┌───────────┬───────────┐  │         │
│            │  │ Analyst   │ Search    │  │         │
│            │  │(Semantic  │(Incident  │  │         │
│            │  │ View)     │ Search)   │  │         │
│            │  └───────────┴───────────┘  │         │
│            └─────────────────────────────┘         │
└───────────────────────────────────────────────────┘
```

---

## Step 1: Creating the Cortex Search Service

We create a Cortex Search Service to enable full-text search of incident history.

### 1.1 Creating the Search View

```sql
-- =============================================
-- Step 1.1: Creating the search view
-- =============================================
USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

CREATE OR REPLACE VIEW V_INCIDENT_SEARCH AS
SELECT
    COALESCE(i.RAW:short_description::STRING, '') || ' ' || COALESCE(i.RAW:description::STRING, '') AS search_text,
    i.RAW:number::STRING AS incident_number,
    i.RAW:category::STRING AS category,
    CASE i.RAW:priority::STRING
        WHEN '1' THEN '1 - Critical'
        WHEN '2' THEN '2 - High'
        WHEN '3' THEN '3 - Moderate'
        WHEN '4' THEN '4 - Low'
        WHEN '5' THEN '5 - Planning'
        ELSE i.RAW:priority::STRING
    END AS priority_label,
    CASE i.RAW:state::STRING
        WHEN '1' THEN 'New'
        WHEN '2' THEN 'In Progress'
        WHEN '3' THEN 'On Hold'
        WHEN '6' THEN 'Resolved'
        WHEN '7' THEN 'Closed'
        WHEN '8' THEN 'Canceled'
        ELSE i.RAW:state::STRING
    END AS state_label,
    g.RAW:name::STRING AS assignment_group_name,
    i.SYS_ID AS sys_id
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT i
LEFT JOIN SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP g
    ON i.RAW:assignment_group:value::STRING = g.SYS_ID AND g.IS_DELETED = FALSE
WHERE i.IS_DELETED = FALSE
  AND i.RAW:short_description::STRING IS NOT NULL;
```

### 1.2 Creating the Cortex Search Service

```sql
-- =============================================
-- Step 1.2: Creating the Cortex Search Service
-- =============================================
CREATE OR REPLACE CORTEX SEARCH SERVICE SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE
  ON search_text
  ATTRIBUTES incident_number, category, priority_label
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Full-text search service for incident history'
AS (
  SELECT
    search_text,
    incident_number,
    category,
    priority_label,
    state_label,
    assignment_group_name,
    sys_id
  FROM SERVICENOW_HANDSON.ANALYTICS.V_INCIDENT_SEARCH
);
```

> **Notes**:
> - `ON search_text`: Specifies the text column to search (summary + detailed description concatenated)
> - `ATTRIBUTES`: Metadata columns used for filtering and result display
> - `TARGET_LAG`: Refresh delay after source data updates (1 hour)

---

## Step 2: Creating the Cortex Agent

We create an AI agent that integrates the Semantic View (data analysis) and Cortex Search Service (incident search).

```sql
-- =============================================
-- Step 2: Creating the Cortex Agent
-- =============================================
CREATE OR REPLACE AGENT SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT
  COMMENT = 'IT operations support AI agent - integrates data analysis and incident search'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    response: "You are an IT operations support AI assistant. Please respond in Japanese. Include specific numbers in data analysis results. Include incident numbers in incident search results."
    orchestration: "Use the Analyst tool for quantitative analysis (MTTR, SLA compliance rate, counts, event log analysis, etc.). Use the Search tool for detailed search of past incidents or similar incident search. IT_EVENT_LOGS contains 50 million IT infrastructure events. Use DT_EVENT_INCIDENT_CORRELATION for event-incident correlation analysis."
    sample_questions:
      - question: "Show MTTR by category"
      - question: "How many SLA violations are there?"
      - question: "Search for network-related incidents"
      - question: "What is the total event log count?"
      - question: "What is the comparison of event counts and incident counts by category?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Analyst"
        description: "Quantitative analysis of ServiceNow incident data and IT infrastructure event logs (MTTR, SLA compliance rate, team performance, event log aggregation, event x incident correlation analysis, etc.)"
    - tool_spec:
        type: "cortex_search"
        name: "IncidentSearch"
        description: "Full-text search of past incident history (fault details, remediation actions, similar incidents, etc.)"

  tool_resources:
    Analyst:
      semantic_view: "SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
    IncidentSearch:
      search_service: "SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE"
      max_results: "5"
  $$;
```

> **Notes**:
> - `models.orchestration: auto`: Snowflake automatically selects the optimal LLM
> - `instructions.response`: Defines the agent's response style (Japanese language support)
> - `instructions.orchestration`: Defines tool selection rules
> - `execution_environment`: Specifies the warehouse where the Analyst tool executes SQL (**required**)
> - `tools`: Specifies the 2 tools available to the agent
>   - `cortex_analyst_text_to_sql`: Data analysis via Semantic View
>   - `cortex_search`: Full-text search of incident history

---

## Step 3: Testing the Agent

### 3.1 Testing in Snowsight

1. Log in to Snowsight
2. Select **AI & ML > Agents** from the left menu
3. Select `IT_OPS_AGENT`
4. Test the following scenarios in the playground

### 3.2 Testing with SQL

```sql
-- =============================================
-- Step 3: Testing the Agent
-- =============================================
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Show MTTR by category"}]}]}',
  TRUE
);
```

### Test Scenarios

| Scenario | Input | Expected Behavior |
|---|---|---|
| Data Analysis | "Show the average MTTR by category" | Analyst tool generates and executes SQL, responds with numbers |
| Incident Search | "Are there incidents about VPN connection failures?" | Search tool responds with incident numbers |
| Compound Question | "What are the network-related trends and past responses?" | Responds using both Analyst + Search |

---

## Step 4: Creating the App with Streamlit in Snowflake

We publish the AI agent as a web app with a dashboard.

### 4.1 Creating the Stage

```sql
-- =============================================
-- Step 4.1: Creating the Streamlit stage
-- =============================================
CREATE STAGE IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for Streamlit app';
```

### 4.2 Uploading the Python File

Execute the following in a Snowsight SQL worksheet (adjust the file path as needed):

```sql
-- =============================================
-- Step 4.2: Uploading the Python file
-- =============================================
PUT 'file:///path/to/streamlit_app.py'
  @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE/
  AUTO_COMPRESS = FALSE
  OVERWRITE = TRUE;
```

> **Note**: The `PUT` command can be executed from a SQL worksheet. The file is uploaded from your local PC.

### 4.3 Creating the Streamlit App

```sql
-- =============================================
-- Step 4.3: Creating the Streamlit app
-- =============================================
CREATE OR REPLACE STREAMLIT SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP
  ROOT_LOCATION = '@SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH'
  TITLE = 'IT Operations Support AI Agent'
  COMMENT = 'ServiceNow IT operations data dashboard + Cortex Agent chat';
```

### 4.4 Verifying the App

1. Select **Streamlit** from the Snowsight left menu
2. Click `IT_OPS_AGENT_APP`
3. Verify the 2 tabs:
   - **Dashboard**: KPI cards, monthly trends, category/priority analysis, team performance
   - **AI Chat**: Conversation with Cortex Agent (with sample question buttons)

> **Tip**: Streamlit in Snowflake can be deployed with SQL alone, so no local environment or CLI is needed. Workshop participants can complete everything in the browser.

---

## Step 5: (Reference) Connecting to Snowflake CoWork

By connecting the agent to Snowflake CoWork (Snowflake Intelligence), users in the organization can use it in a chat format, separate from the Streamlit app.

1. Select **AI & ML > Agents** from the Snowsight left menu
2. Select `IT_OPS_AGENT`
3. Click the **Connect to CoWork** button
4. Set the display name and icon, then connect

---

## Step 6: (Reference) Cleanup

To delete resources after the workshop:

```sql
-- =============================================
-- Step 6: Cleanup (only if needed)
-- =============================================
USE ROLE ACCOUNTADMIN;

-- Delete the Streamlit app
DROP STREAMLIT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- Delete the Cortex Agent
DROP AGENT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT;

-- Delete the Cortex Search Service
DROP CORTEX SEARCH SERVICE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE;

-- Delete the search view
DROP VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.V_INCIDENT_SEARCH;

-- Delete the Semantic View
DROP SEMANTIC VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;

-- Delete the Dynamic Tables
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE;

-- Delete the workshop database
DROP DATABASE IF EXISTS SERVICENOW_HANDSON;

-- Pause the Connector
USE APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
CALL PAUSE_CONNECTOR();
```

---

## Summary

What was accomplished in this part:

1. Created a **Cortex Search Service** (full-text search for incident history)
2. Created a **Cortex Agent** (AI agent integrating Analyst + Search)
3. Performed **testing** (data analysis, incident search, compound questions)
4. Built a dashboard + AI chat app with **Streamlit in Snowflake**

---

## Workshop Overall Review

Through the 5 parts, we experienced the following Snowflake features end-to-end:

| Part | Feature | Deliverable |
|---|---|---|
| Part 1 | Snowflake Connector for ServiceNow (OAuth2) | Secure automatic sync of ServiceNow data |
| Part 2 | Dynamic Tables | Declarative data transformation pipeline |
| Part 3 | Snowflake Notebooks | Interactive analysis and visualization |
| Part 4 | Semantic View + Cortex Analyst | Natural language data analysis |
| Part 5 | Cortex Agent + Streamlit in Snowflake | AI agent app (dashboard + chat) |

**Key Takeaway**: From secure data ingestion from ServiceNow (OAuth2 authentication) to AI agent app, everything is completed entirely on Snowflake. No local environment or third-party tools are required.
