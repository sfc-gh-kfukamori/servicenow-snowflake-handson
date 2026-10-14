# =============================================================================
# ServiceNow IT Operations Support Streamlit App
# =============================================================================
# Dashboard + AI Chat app running on Streamlit in Snowflake (SiS)
#
# 3 Tabs:
#   1. Dashboard: KPIs, monthly trends, by-category, team performance
#   2. Correlation Analysis: S3 event logs x ServiceNow incident correlation
#   3. AI Chat: Natural language data analysis via Cortex Agent (DATA_AGENT_RUN)
#
# Note: SiS uses an older Streamlit version with the following limitations:
#   - st.chat_input / st.chat_message are unavailable -> use st.form + st.text_input
#   - st.rerun() is used to refresh the app after state changes
#   - st.dataframe() hide_index argument is unavailable
# =============================================================================

import streamlit as st
import json
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="IT Ops AI Agent", page_icon="🤖", layout="wide")

# Fully qualified name of the agent (Cortex Agent created in Part 5)
AGENT_FQN = "SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT"

# Snowpark session (obtained via get_active_session() in SiS)
session = get_active_session()

CUSTOM_CSS = """
<style>
.user-bubble {
    background: linear-gradient(135deg, #29B5E8 0%, #1a8bb8 100%);
    color: white; padding: 12px 18px; border-radius: 18px 18px 4px 18px;
    margin: 8px 0; max-width: 80%; float: right; clear: both; font-size: 15px;
    box-shadow: 0 2px 8px rgba(41,181,232,0.2);
}
.agent-bubble {
    background: #f0f2f6; color: #1a1a2e; padding: 14px 18px;
    border-radius: 18px 18px 18px 4px; margin: 8px 0; max-width: 90%;
    clear: both; font-size: 15px; line-height: 1.6;
    box-shadow: 0 1px 4px rgba(0,0,0,0.06);
}
.thinking-box {
    background: #fff8e1; border-left: 3px solid #ffc107;
    padding: 8px 14px; margin: 6px 0; border-radius: 4px; font-size: 13px; color: #6d5c00;
}
.tool-box {
    background: #e8f5e9; border-left: 3px solid #4caf50;
    padding: 8px 14px; margin: 6px 0; border-radius: 4px; font-size: 13px; color: #1b5e20;
}
.clearfix { clear: both; }
.kpi-card {
    background: white; border-radius: 12px; padding: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08); text-align: center;
}
.kpi-value { font-size: 32px; font-weight: 700; color: #29B5E8; }
.kpi-label { font-size: 13px; color: #64748b; margin-top: 4px; }
</style>
"""
st.markdown(CUSTOM_CSS, unsafe_allow_html=True)


# ======== Agent functions ========
# Calls DATA_AGENT_RUN and parses the response JSON
# Response format: {content: [{type: "thinking"}, {type: "tool_use"}, {type: "text"}]}

def call_agent(question):
    request_body = json.dumps({
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": question}]}
        ]
    })
    result = session.sql(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?, TRUE) AS response",
        params=[AGENT_FQN, request_body]
    ).collect()

    if not result:
        return {"text": "No response received from the agent.", "steps": []}

    raw = result[0]["RESPONSE"]
    try:
        resp = json.loads(raw) if isinstance(raw, str) else raw
    except (json.JSONDecodeError, TypeError):
        return {"text": f"Parse error: {str(raw)[:300]}", "steps": []}

    text, steps, content_items = "", [], []
    if isinstance(resp, dict) and "content" in resp:
        content_items = resp["content"] if isinstance(resp["content"], list) else []

    for item in content_items:
        if not isinstance(item, dict):
            continue
        t = item.get("type", "")
        if t == "text":
            text += item.get("text", "")
        elif t == "thinking":
            th = item.get("thinking", {})
            if isinstance(th, dict):
                steps.append({"type": "thinking", "text": th.get("text", "")})
        elif t == "tool_use":
            tu = item.get("tool_use", {})
            if isinstance(tu, dict):
                steps.append({"type": "tool", "name": tu.get("name", "")})
        elif t == "tool_result":
            tr = item.get("tool_result", {})
            if isinstance(tr, dict):
                for rc in (tr.get("content", []) if isinstance(tr.get("content"), list) else []):
                    if isinstance(rc, dict) and "json" in rc:
                        sql_text = rc["json"].get("sql", "")
                        if sql_text:
                            steps.append({"type": "sql", "text": sql_text})

    return {"text": text or "Unable to retrieve response text.", "steps": steps}


def render_user_message(content):
    st.markdown(f'<div class="user-bubble">{content}</div><div class="clearfix"></div>', unsafe_allow_html=True)


def render_agent_message(result):
    if result.get("steps"):
        with st.expander("🔧 Agent Processing Steps", expanded=False):
            for step in result["steps"]:
                if step["type"] == "thinking":
                    st.markdown(f'<div class="thinking-box">💭 {step["text"][:200]}</div>', unsafe_allow_html=True)
                elif step["type"] == "tool":
                    st.markdown(f'<div class="tool-box">🔧 Used <b>{step["name"]}</b></div>', unsafe_allow_html=True)
                elif step["type"] == "sql":
                    st.code(step["text"], language="sql")
    st.markdown(f'<div class="agent-bubble">{result["text"]}</div><div class="clearfix"></div>', unsafe_allow_html=True)


# ======== Dashboard functions ========
# Aggregates DT_INCIDENT_ENRICHED and DT_TEAM_PERFORMANCE to display KPIs and charts
# @st.cache_data(ttl=300) caches for 5 minutes to reduce query frequency

@st.cache_data(ttl=300)
def load_kpis():
    return session.sql("""
        SELECT
            COUNT(*) AS total_incidents,
            COUNT(CASE WHEN state_label IN ('New','In Progress') THEN 1 END) AS open_incidents,
            ROUND(AVG(mttr_hours), 1) AS avg_mttr,
            ROUND(COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0
                / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0), 1) AS sla_pct
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
    """).to_pandas()


@st.cache_data(ttl=300)
def load_monthly_trend():
    return session.sql("""
        SELECT DATE_TRUNC('month', opened_at)::DATE AS month,
            COUNT(*) AS incidents,
            ROUND(AVG(mttr_hours), 1) AS avg_mttr
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
        WHERE opened_at IS NOT NULL
        GROUP BY 1 ORDER BY 1
    """).to_pandas()


@st.cache_data(ttl=300)
def load_category_stats():
    return session.sql("""
        SELECT category,
            COUNT(*) AS incidents,
            ROUND(AVG(mttr_hours), 1) AS avg_mttr
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
        WHERE category IS NOT NULL AND category != ''
        GROUP BY 1 ORDER BY incidents DESC
    """).to_pandas()


@st.cache_data(ttl=300)
def load_priority_dist():
    return session.sql("""
        SELECT priority_label, COUNT(*) AS incidents
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
        WHERE priority_label IS NOT NULL
        GROUP BY 1 ORDER BY 1
    """).to_pandas()


@st.cache_data(ttl=300)
def load_team_perf():
    return session.sql("""
        SELECT assignment_group, total_incidents, avg_mttr_hours,
            sla_compliance_pct, top_category
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
        ORDER BY total_incidents DESC
    """).to_pandas()


def render_dashboard():
    st.markdown("## 📊 Incident Dashboard")

    try:
        kpis = load_kpis()
        k = kpis.iloc[0]

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Total Incidents", f"{int(k['TOTAL_INCIDENTS']):,}")
        c2.metric("Open Incidents", f"{int(k['OPEN_INCIDENTS']):,}")
        c3.metric("Avg MTTR (hours)", f"{k['AVG_MTTR']:.1f}")
        c4.metric("SLA Compliance Rate", f"{k['SLA_PCT']:.1f}%")
    except Exception as e:
        st.error(f"KPI retrieval error: {e}")

    st.divider()

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("### 📈 Monthly Incident Trend")
        try:
            df_monthly = load_monthly_trend()
            if not df_monthly.empty:
                st.bar_chart(df_monthly.set_index("MONTH")["INCIDENTS"])
            else:
                st.info("No data available")
        except Exception as e:
            st.error(f"Monthly data retrieval error: {e}")

    with col2:
        st.markdown("### 🏷️ Incidents by Category")
        try:
            df_cat = load_category_stats()
            if not df_cat.empty:
                st.bar_chart(df_cat.set_index("CATEGORY")["INCIDENTS"])
            else:
                st.info("No data available")
        except Exception as e:
            st.error(f"Category data retrieval error: {e}")

    st.divider()

    col3, col4 = st.columns(2)

    with col3:
        st.markdown("### 🎯 Priority Distribution")
        try:
            df_pri = load_priority_dist()
            if not df_pri.empty:
                st.bar_chart(df_pri.set_index("PRIORITY_LABEL")["INCIDENTS"])
            else:
                st.info("No data available")
        except Exception as e:
            st.error(f"Priority data retrieval error: {e}")

    with col4:
        st.markdown("### 👥 Team Performance")
        try:
            df_team = load_team_perf()
            if not df_team.empty:
                st.dataframe(df_team.rename(columns={
                    "ASSIGNMENT_GROUP": "Team",
                    "TOTAL_INCIDENTS": "Count",
                    "AVG_MTTR_HOURS": "Avg MTTR (h)",
                    "SLA_COMPLIANCE_PCT": "SLA Compliance (%)",
                    "TOP_CATEGORY": "Top Category"
                }))
            else:
                st.info("No data available")
        except Exception as e:
            st.error(f"Team data retrieval error: {e}")


# ======== Correlation Tab ========
# Correlation analysis between IT event logs loaded from S3 and ServiceNow incidents
# Uses DT_EVENT_INCIDENT_CORRELATION (daily x category aggregation DT)

@st.cache_data(ttl=300)
def load_correlation():
    return session.sql("""
        SELECT event_date, category, event_count, critical_event_count,
            error_event_count, incident_count, avg_mttr_hours
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
        WHERE incident_count > 0
        ORDER BY event_date
    """).to_pandas()


@st.cache_data(ttl=300)
def load_event_summary():
    return session.sql("""
        SELECT category,
            SUM(event_count) AS total_events,
            SUM(critical_event_count) AS total_critical,
            SUM(incident_count) AS total_incidents
        FROM SERVICENOW_HANDSON.ANALYTICS.DT_EVENT_INCIDENT_CORRELATION
        GROUP BY category
        ORDER BY total_events DESC
    """).to_pandas()


def render_correlation():
    st.markdown("## 🔗 Event x Incident Correlation Analysis")
    st.caption("Correlation between IT event logs loaded from S3 and ServiceNow incidents")

    try:
        df_summary = load_event_summary()
        if df_summary.empty:
            st.warning("No data in DT_EVENT_INCIDENT_CORRELATION. Please complete Part 1.5.")
            return

        c1, c2, c3 = st.columns(3)
        c1.metric("Total Events", f"{int(df_summary['TOTAL_EVENTS'].sum()):,}")
        c2.metric("CRITICAL Events", f"{int(df_summary['TOTAL_CRITICAL'].sum()):,}")
        c3.metric("Related Incidents", f"{int(df_summary['TOTAL_INCIDENTS'].sum()):,}")

        st.divider()

        col1, col2 = st.columns(2)
        with col1:
            st.markdown("### Events vs Incidents by Category")
            st.dataframe(df_summary.rename(columns={
                "CATEGORY": "Category",
                "TOTAL_EVENTS": "Events",
                "TOTAL_CRITICAL": "CRITICAL",
                "TOTAL_INCIDENTS": "Incidents"
            }))

        with col2:
            st.markdown("### Events by Category")
            st.bar_chart(df_summary.set_index("CATEGORY")["TOTAL_EVENTS"])

        st.divider()
        st.markdown("### Daily Event x Incident Trend")
        df_corr = load_correlation()
        if not df_corr.empty:
            df_daily = df_corr.groupby("EVENT_DATE").agg(
                {"EVENT_COUNT": "sum", "INCIDENT_COUNT": "sum"}).reset_index()
            st.line_chart(df_daily.set_index("EVENT_DATE"))

    except Exception as e:
        if "does not exist" in str(e).lower():
            st.info("DT_EVENT_INCIDENT_CORRELATION has not been created yet. It will appear after completing Part 1.5.")
        else:
            st.error(f"Correlation data retrieval error: {e}")


# ======== Chat Tab ========
# Interactive chat UI using Cortex Agent (DATA_AGENT_RUN)
# Sample question button -> pending_question -> call_agent -> display result

def render_chat():
    st.markdown("## 🤖 AI Agent")
    st.caption("Ask questions about ServiceNow incident data in natural language")

    SAMPLE_QUESTIONS = [
        "📊 Show average MTTR by category",
        "🎯 How many SLA violations are there?",
        "🔍 Search for network-related incidents",
        "👥 Compare team performance",
    ]

    if not st.session_state.messages and st.session_state.pending_question is None:
        cols = st.columns(4)
        for i, q in enumerate(SAMPLE_QUESTIONS):
            with cols[i]:
                if st.button(q, key=f"s_{i}"):
                    st.session_state.pending_question = q.split(" ", 1)[1] if " " in q else q
                    st.rerun()

    for msg in st.session_state.messages:
        if msg["role"] == "user":
            render_user_message(msg["content"])
        else:
            render_agent_message(msg["result"])

    if st.session_state.pending_question:
        question = st.session_state.pending_question
        st.session_state.pending_question = None
        st.session_state.messages.append({"role": "user", "content": question})
        render_user_message(question)
        with st.spinner("🤖 Agent is analyzing..."):
            try:
                result = call_agent(question)
            except Exception as e:
                result = {"text": f"Error: {str(e)}", "steps": []}
        st.session_state.messages.append({"role": "assistant", "result": result})
        render_agent_message(result)

    st.markdown("---")
    with st.form("q_form", clear_on_submit=True):
        c1, c2 = st.columns([6, 1])
        with c1:
            user_input = st.text_input("Question", key="q_input", label_visibility="collapsed",
                                       placeholder="Enter your question...")
        with c2:
            submitted = st.form_submit_button("Submit")

    if submitted and user_input.strip():
        st.session_state.pending_question = user_input.strip()
        st.rerun()


# ======== Main: Tab layout and sidebar ========

if "messages" not in st.session_state:
    st.session_state.messages = []
if "pending_question" not in st.session_state:
    st.session_state.pending_question = None

tab1, tab2, tab3 = st.tabs(["📊 Dashboard", "🔗 Correlation", "🤖 AI Chat"])

with tab1:
    render_dashboard()

with tab2:
    render_correlation()

with tab3:
    render_chat()

with st.sidebar:
    st.markdown("### IT Operations Intelligence")
    st.markdown("""
**ServiceNow x Snowflake**

📊 **Dashboard** — Monitor current status with KPIs & charts
🔗 **Correlation** — Event log x incident correlation
🤖 **AI Chat** — Deep analysis with Cortex Agent
    """)
    st.divider()
    st.markdown("**Data Sources:**")
    st.markdown("- DT_INCIDENT_ENRICHED\n- DT_TEAM_PERFORMANCE\n- DT_EVENT_INCIDENT_CORRELATION\n- Cortex Search Service")
    st.divider()
    if st.button("🗑️ Reset Chat History"):
        st.session_state.messages = []
        st.session_state.pending_question = None
        st.rerun()
