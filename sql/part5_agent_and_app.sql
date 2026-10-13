-- =============================================================================
-- Part 5: AI Agent App (Cortex Agent + Streamlit in Snowflake)
-- =============================================================================
-- Create an AI agent that integrates the Semantic View (data analysis) and
-- Cortex Search Service (incident search), and build a dashboard + chat UI
-- with Streamlit in Snowflake.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- -----------------------------------------------------------------------------
-- Step 1: Create the Cortex Search Service
-- Full-text search service for incident history.
-- First, create a view that consolidates incident information for search,
-- then build the Cortex Search Service on top of it.
-- -----------------------------------------------------------------------------

-- Search view: References raw tables from the Connector directly
-- (DT_INCIDENT_ENRICHED uses FULL refresh, which is incompatible with
-- Cortex Search)
CREATE OR REPLACE VIEW V_INCIDENT_SEARCH AS
SELECT
    i.SYS_ID AS sys_id,
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
    COALESCE(i.RAW:short_description::STRING, '') || ' ' ||
    COALESCE(i.RAW:description::STRING, '') AS search_text
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT i
LEFT JOIN SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP g
    ON i.RAW:assignment_group:value::STRING = g.SYS_ID AND g.IS_DELETED = FALSE
WHERE i.IS_DELETED = FALSE
  AND i.RAW:short_description::STRING IS NOT NULL;

-- Cortex Search Service: Generates embedding vectors using
-- snowflake-arctic-embed-m-v1.5 to enable semantic search
CREATE OR REPLACE CORTEX SEARCH SERVICE INCIDENT_SEARCH_SERVICE
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
  FROM V_INCIDENT_SEARCH
);

-- -----------------------------------------------------------------------------
-- Step 2: Create the Cortex Agent
-- Integrates Analyst (data analysis via Semantic View) and Search (incident
-- full-text search) into a single agent. Simply ask a question in natural
-- language and the appropriate tool is automatically selected.
--
-- orchestration: auto -> Snowflake automatically selects the optimal LLM
-- execution_environment: Specifies the warehouse for Analyst SQL execution
--                        (required)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE AGENT IT_OPS_AGENT
  COMMENT = 'IT operations support AI agent - integrates data analysis and incident search'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    response: "You are an IT operations support AI assistant. Please respond in the same language as the user's question. Include specific numbers in data analysis results. Include incident numbers in incident search results."
    orchestration: "Use the Analyst tool for quantitative analysis (MTTR, SLA compliance rate, counts, event log analysis, etc.). Use the Search tool for detailed searches of past incidents or similar incident searches. The event logs (IT_EVENT_LOGS) contain 50 million IT infrastructure events. Use DT_EVENT_INCIDENT_CORRELATION for correlation analysis between events and incidents."
    sample_questions:
      - question: "What is the MTTR by category?"
      - question: "How many SLA violations are there?"
      - question: "Search for network-related incidents"
      - question: "What is the total number of event logs?"
      - question: "What is the comparison of event count and incident count by category?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Analyst"
        description: "Quantitative analysis of ServiceNow incident data and IT infrastructure event logs (MTTR, SLA compliance rate, team performance, event log aggregation, event x incident correlation analysis, etc.)"
    - tool_spec:
        type: "cortex_search"
        name: "IncidentSearch"
        description: "Full-text search of past incident history (failure details, remediation actions, similar incidents, etc.)"

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

-- -----------------------------------------------------------------------------
-- Step 3: Test the Agent (execute from SQL)
-- DATA_AGENT_RUN arguments: agent name, request body ($$...$$ literal)
-- content is passed as an array in the format:
-- [{type: "text", text: "question"}]
-- -----------------------------------------------------------------------------
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT',
    $${"messages": [{"role": "user", "content": [{"type": "text", "text": "What is the MTTR by category?"}]}]}$$
  )
):content[2]:text::STRING AS agent_response;

-- -----------------------------------------------------------------------------
-- Step 4: Deploy Streamlit in Snowflake
-- Upload streamlit_app.py to an internal stage and create a STREAMLIT object.
-- The stage serves as the source code location for the app.
-- -----------------------------------------------------------------------------

-- Create an internal stage for the app
CREATE STAGE IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- Upload the local streamlit_app.py to the stage
-- * For Snowsight, upload via the UI instead of using PUT
PUT file://streamlit_app.py @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE
  AUTO_COMPRESS = FALSE
  OVERWRITE = TRUE;

-- Create the Streamlit app
CREATE OR REPLACE STREAMLIT SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP
  ROOT_LOCATION = '@SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = COMPUTE_WH
  COMMENT = 'ServiceNow IT operations data dashboard + Cortex Agent chat';

-- Open IT_OPS_AGENT_APP from Snowsight left menu > Streamlit
