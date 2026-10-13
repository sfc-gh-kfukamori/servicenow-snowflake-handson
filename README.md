# ServiceNow x Snowflake Hands-On

## Building an IT Operations Intelligence Platform

This is a hands-on workshop that covers the end-to-end process of ingesting ServiceNow data into Snowflake, then performing data transformation, analysis, visualization, and building an AI agent application.

---

## Overall Architecture Diagram

```
ServiceNow PDI
  │
  │ Snowflake Connector for ServiceNow
  │ (OAuth 2.0 Authentication / Auto Sync)
  ▼
┌──────────────────────────────────────────────────────┐
│                    Snowflake                          │
│                                                       │
│  ┌─────────────────────────┐ ┌───────────────────┐  │
│  │ Raw Data (Connector)    │ │ S3 External Stage │  │
│  │ incident, sys_user,     │ │ IT Event Logs     │  │
│  │ sys_user_group, task_sla│ │ (5 million rows)  │  │
│  └─────────────┬───────────┘ └────────┬──────────┘  │
│                │                      │              │
│                ▼                      ▼              │
│  ┌─────────────────────────────────────────────────┐  │
│  │ Dynamic Tables (Analytics Pipeline)             │  │
│  │  DT_INCIDENT_ENRICHED (JOIN: 3 tables)          │  │
│  │  DT_INCIDENT_DAILY_STATS (Daily Aggregation)    │  │
│  │  DT_SLA_ANALYSIS (SLA Analysis)                 │  │
│  │  DT_TEAM_PERFORMANCE (Per-Team Aggregation)     │  │
│  │  DT_EVENT_INCIDENT_CORRELATION (Correlation)    │  │
│  └──────┬──────────────────┬───────────────────────┘  │
│         │                  │                           │
│         ▼                  ▼                           │
│  ┌─────────────┐  ┌──────────────────┐                │
│  │ Notebooks   │  │ Semantic View    │                │
│  │ (Analysis/  │  │ + Cortex Analyst │                │
│  │  Viz)       │  │                  │                │
│  └─────────────┘  └────────┬─────────┘                │
│                            │                           │
│                   ┌────────┴─────────┐                 │
│                   │  Cortex Agent    │                 │
│                   │  (Analyst +      │                 │
│                   │   Search)        │                 │
│                   └────────┬─────────┘                 │
│                            │                           │
│                   ┌────────┴─────────┐                 │
│                   │ Streamlit in     │                 │
│                   │  Snowflake       │                 │
│                   │ (Dashboard       │                 │
│                   │  + AI Chat)      │                 │
│                   └──────────────────┘                 │
└──────────────────────────────────────────────────────┘
```

---

## Hands-On Structure

| Part | Content | Snowflake Features Used | Guide |
|---|---|---|---|
| **Part 1** | Data Loading | Snowflake Connector for ServiceNow | [part1_data_loading.md](part1_data_loading.md) |
| **Part 1.5** | External Data Loading | S3 External Stage, COPY INTO, Warehouse Size Comparison | [part1_5_s3_data_loading.md](part1_5_s3_data_loading.md) |
| **Part 2** | Data Transformation | Dynamic Tables | [part2_dynamic_tables.md](part2_dynamic_tables.md) |
| **Part 3** | Analysis & Visualization | Snowflake Notebooks (SQL + Python) | [part3_analysis_notebook.md](part3_analysis_notebook.md) |
| **Part 4** | Natural Language Analysis | Semantic View, Cortex Analyst | [part4_semantic_view.md](part4_semantic_view.md) |
| **Part 5** | AI Agent Application | Cortex Agent, Cortex Search, Streamlit in Snowflake | [part5_ai_agent_app.md](part5_ai_agent_app.md) |

---

## Prerequisites

### Snowflake
- Snowflake account (ACCOUNTADMIN role)
- Snowflake Connector for ServiceNow installed
  - Obtain and install "Snowflake Connector for ServiceNow" from the Snowflake Marketplace

### ServiceNow
- ServiceNow Developer Program account
- PDI (Personal Developer Instance)
  - Can be created for free at [developer.servicenow.com](https://developer.servicenow.com/)

> **No local environment is required.** All steps can be completed entirely within Snowsight (Snowflake's Web UI).

---

## ServiceNow Tables Used

| Table Name | Description | Purpose | How to Verify in ServiceNow |
|---|---|---|---|
| `incident` | Incident Management | Primary analysis target | Incident > All |
| `sys_user` | User Information | Joining assignee details | User Administration > Users |
| `sys_user_group` | User Groups | Joining team information | User Administration > Groups |
| `task_sla` | SLA Achievement Status | SLA Analysis | (System table — verify on the Snowflake side) |

---

## Snowflake Objects Created

| Object | Type | Description |
|---|---|---|
| `SERVICENOW_DEST_DB.DEST_SCHEMA` | Schema | Connector sync destination |
| `SERVICENOW_HANDSON.ANALYTICS` | Schema | For analytics |
| `DT_INCIDENT_ENRICHED` | Dynamic Table | Incident details (JOIN: incident + sys_user + sys_user_group) |
| `DT_INCIDENT_DAILY_STATS` | Dynamic Table | Daily incident statistics |
| `DT_SLA_ANALYSIS` | Dynamic Table | SLA achievement analysis (JOIN: task_sla + incident) |
| `DT_TEAM_PERFORMANCE` | Dynamic Table | Per-team performance |
| `IT_EVENT_LOGS` | Table | IT event logs loaded from S3 (50 million rows x 10 files) |
| `DT_EVENT_INCIDENT_CORRELATION` | Dynamic Table | Event log x incident correlation analysis |
| `S3_EVENT_STAGE` | External Stage | Connection to S3 bucket |
| `SERVICENOW_SEMANTIC_VIEW` | Semantic View | Metadata definition for natural language analysis (6 tables: incidents + event logs) |
| `INCIDENT_SEARCH_SERVICE` | Cortex Search Service | Full-text search over incident history |
| `IT_OPS_AGENT` | Cortex Agent | AI agent (Analyst + Search, with event log analysis support) |
| `IT_OPS_AGENT_APP` | Streamlit in Snowflake | Dashboard + AI chat UI |

---

## Key Value Propositions for Customers

1. **No-Code Integration**: Automate data ingestion with the ServiceNow Connector. No API development or batch processing required
2. **Declarative Pipelines**: Just write SQL with Dynamic Tables. Snowflake automatically handles scheduling and error handling
3. **Easy AI Adoption**: Simply define a Semantic View to enable natural language analysis. No AI/ML expertise required
4. **End-to-End**: Everything from data ingestion to AI applications is completed within Snowflake. No additional infrastructure needed
5. **Governance**: All data is consolidated within Snowflake, enabling role-based access control
6. **Scalability**: Improve performance simply by changing the warehouse size. No changes to SQL or infrastructure required
