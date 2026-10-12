# =============================================================================
# ServiceNow IT運用支援 Streamlit アプリ
# =============================================================================
# Streamlit in Snowflake (SiS) で動作するダッシュボード + AI チャットアプリ
#
# 3つのタブ:
#   1. ダッシュボード: KPI、月次推移、カテゴリ別、チーム別パフォーマンス
#   2. 相関分析: S3イベントログ × ServiceNowインシデントの突合分析
#   3. AIチャット: Cortex Agent (DATA_AGENT_RUN) による自然言語データ分析
#
# 注意: SiS は古い Streamlit バージョンのため以下の制約あり:
#   - st.chat_input / st.chat_message は使えない → st.form + st.text_input
#   - st.rerun() は使えない → st.experimental_rerun()
#   - st.dataframe() の hide_index 引数は使えない
# =============================================================================

import streamlit as st
import json
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="IT運用支援AIエージェント", page_icon="🤖", layout="wide")

# エージェントの完全修飾名（Part 5 で作成した Cortex Agent）
AGENT_FQN = "SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT"

# Snowpark セッション（SiS では get_active_session() で取得）
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
# DATA_AGENT_RUN を呼び出し、レスポンス JSON をパースする
# レスポンス形式: {content: [{type: "thinking"}, {type: "tool_use"}, {type: "text"}]}

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
        return {"text": "エージェントから応答がありませんでした。", "steps": []}

    raw = result[0]["RESPONSE"]
    try:
        resp = json.loads(raw) if isinstance(raw, str) else raw
    except (json.JSONDecodeError, TypeError):
        return {"text": f"パースエラー: {str(raw)[:300]}", "steps": []}

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

    return {"text": text or "応答テキストを取得できませんでした。", "steps": steps}


def render_user_message(content):
    st.markdown(f'<div class="user-bubble">{content}</div><div class="clearfix"></div>', unsafe_allow_html=True)


def render_agent_message(result):
    if result.get("steps"):
        with st.expander("🔧 エージェントの処理ステップ", expanded=False):
            for step in result["steps"]:
                if step["type"] == "thinking":
                    st.markdown(f'<div class="thinking-box">💭 {step["text"][:200]}</div>', unsafe_allow_html=True)
                elif step["type"] == "tool":
                    st.markdown(f'<div class="tool-box">🔧 <b>{step["name"]}</b> を使用</div>', unsafe_allow_html=True)
                elif step["type"] == "sql":
                    st.code(step["text"], language="sql")
    st.markdown(f'<div class="agent-bubble">{result["text"]}</div><div class="clearfix"></div>', unsafe_allow_html=True)


# ======== Dashboard functions ========
# DT_INCIDENT_ENRICHED, DT_TEAM_PERFORMANCE を集計してKPIとチャートを表示
# @st.cache_data(ttl=300) で5分間キャッシュしてクエリ回数を削減

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
    st.markdown("## 📊 インシデントダッシュボード")

    try:
        kpis = load_kpis()
        k = kpis.iloc[0]

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("総インシデント数", f"{int(k['TOTAL_INCIDENTS']):,}")
        c2.metric("オープン件数", f"{int(k['OPEN_INCIDENTS']):,}")
        c3.metric("平均MTTR（時間）", f"{k['AVG_MTTR']:.1f}")
        c4.metric("SLA遵守率", f"{k['SLA_PCT']:.1f}%")
    except Exception as e:
        st.error(f"KPI取得エラー: {e}")

    st.divider()

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("### 📈 月次インシデント推移")
        try:
            df_monthly = load_monthly_trend()
            if not df_monthly.empty:
                st.bar_chart(df_monthly.set_index("MONTH")["INCIDENTS"])
            else:
                st.info("データがありません")
        except Exception as e:
            st.error(f"月次データ取得エラー: {e}")

    with col2:
        st.markdown("### 🏷️ カテゴリ別インシデント数")
        try:
            df_cat = load_category_stats()
            if not df_cat.empty:
                st.bar_chart(df_cat.set_index("CATEGORY")["INCIDENTS"])
            else:
                st.info("データがありません")
        except Exception as e:
            st.error(f"カテゴリデータ取得エラー: {e}")

    st.divider()

    col3, col4 = st.columns(2)

    with col3:
        st.markdown("### 🎯 優先度別分布")
        try:
            df_pri = load_priority_dist()
            if not df_pri.empty:
                st.bar_chart(df_pri.set_index("PRIORITY_LABEL")["INCIDENTS"])
            else:
                st.info("データがありません")
        except Exception as e:
            st.error(f"優先度データ取得エラー: {e}")

    with col4:
        st.markdown("### 👥 チーム別パフォーマンス")
        try:
            df_team = load_team_perf()
            if not df_team.empty:
                st.dataframe(df_team.rename(columns={
                    "ASSIGNMENT_GROUP": "チーム",
                    "TOTAL_INCIDENTS": "件数",
                    "AVG_MTTR_HOURS": "平均MTTR(h)",
                    "SLA_COMPLIANCE_PCT": "SLA遵守率(%)",
                    "TOP_CATEGORY": "主カテゴリ"
                }))
            else:
                st.info("データがありません")
        except Exception as e:
            st.error(f"チームデータ取得エラー: {e}")


# ======== Correlation Tab ========
# S3 からロードした IT イベントログと ServiceNow インシデントの突合分析
# DT_EVENT_INCIDENT_CORRELATION（日別×カテゴリ別の集計DT）を利用

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
    st.markdown("## 🔗 イベント × インシデント相関分析")
    st.caption("S3 からロードした IT イベントログと ServiceNow インシデントの突合")

    try:
        df_summary = load_event_summary()
        if df_summary.empty:
            st.warning("DT_EVENT_INCIDENT_CORRELATION にデータがありません。Part 1.5 を完了してください。")
            return

        c1, c2, c3 = st.columns(3)
        c1.metric("総イベント数", f"{int(df_summary['TOTAL_EVENTS'].sum()):,}")
        c2.metric("CRITICAL イベント", f"{int(df_summary['TOTAL_CRITICAL'].sum()):,}")
        c3.metric("関連インシデント", f"{int(df_summary['TOTAL_INCIDENTS'].sum()):,}")

        st.divider()

        col1, col2 = st.columns(2)
        with col1:
            st.markdown("### カテゴリ別 イベント vs インシデント")
            st.dataframe(df_summary.rename(columns={
                "CATEGORY": "カテゴリ",
                "TOTAL_EVENTS": "イベント数",
                "TOTAL_CRITICAL": "CRITICAL",
                "TOTAL_INCIDENTS": "インシデント数"
            }))

        with col2:
            st.markdown("### カテゴリ別イベント数")
            st.bar_chart(df_summary.set_index("CATEGORY")["TOTAL_EVENTS"])

        st.divider()
        st.markdown("### 日別 イベント × インシデント推移")
        df_corr = load_correlation()
        if not df_corr.empty:
            df_daily = df_corr.groupby("EVENT_DATE").agg(
                {"EVENT_COUNT": "sum", "INCIDENT_COUNT": "sum"}).reset_index()
            st.line_chart(df_daily.set_index("EVENT_DATE"))

    except Exception as e:
        if "does not exist" in str(e).lower():
            st.info("DT_EVENT_INCIDENT_CORRELATION がまだ作成されていません。Part 1.5 を完了すると表示されます。")
        else:
            st.error(f"相関データ取得エラー: {e}")


# ======== Chat Tab ========
# Cortex Agent (DATA_AGENT_RUN) を使った対話型チャットUI
# サンプル質問ボタン → pending_question → call_agent → 結果表示

def render_chat():
    st.markdown("## 🤖 AIエージェント")
    st.caption("ServiceNow インシデントデータについて自然言語で質問できます")

    SAMPLE_QUESTIONS = [
        "📊 カテゴリ別の平均MTTRを教えて",
        "🎯 SLA違反の件数は？",
        "🔍 ネットワーク関連のインシデントを検索して",
        "👥 チーム別のパフォーマンスを比較して",
    ]

    if not st.session_state.messages and st.session_state.pending_question is None:
        cols = st.columns(4)
        for i, q in enumerate(SAMPLE_QUESTIONS):
            with cols[i]:
                if st.button(q, key=f"s_{i}"):
                    st.session_state.pending_question = q.split(" ", 1)[1] if " " in q else q
                    st.experimental_rerun()

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
        with st.spinner("🤖 エージェントが分析中..."):
            try:
                result = call_agent(question)
            except Exception as e:
                result = {"text": f"エラー: {str(e)}", "steps": []}
        st.session_state.messages.append({"role": "assistant", "result": result})
        render_agent_message(result)

    st.markdown("---")
    with st.form("q_form", clear_on_submit=True):
        c1, c2 = st.columns([6, 1])
        with c1:
            user_input = st.text_input("質問", key="q_input", label_visibility="collapsed",
                                       placeholder="質問を入力してください...")
        with c2:
            submitted = st.form_submit_button("送信")

    if submitted and user_input.strip():
        st.session_state.pending_question = user_input.strip()
        st.experimental_rerun()


# ======== Main: タブ構成とサイドバー ========

if "messages" not in st.session_state:
    st.session_state.messages = []
if "pending_question" not in st.session_state:
    st.session_state.pending_question = None

tab1, tab2, tab3 = st.tabs(["📊 ダッシュボード", "🔗 相関分析", "🤖 AIチャット"])

with tab1:
    render_dashboard()

with tab2:
    render_correlation()

with tab3:
    render_chat()

with st.sidebar:
    st.markdown("### IT運用インテリジェンス")
    st.markdown("""
**ServiceNow × Snowflake**

📊 **ダッシュボード** — KPI・チャートで現状把握
🔗 **相関分析** — イベントログ×インシデント突合
🤖 **AIチャット** — Cortex Agent で深掘り分析
    """)
    st.divider()
    st.markdown("**データソース:**")
    st.markdown("- DT_INCIDENT_ENRICHED\n- DT_TEAM_PERFORMANCE\n- DT_EVENT_INCIDENT_CORRELATION\n- Cortex Search Service")
    st.divider()
    if st.button("🗑️ チャット履歴リセット"):
        st.session_state.messages = []
        st.session_state.pending_question = None
        st.experimental_rerun()
