# Part 3: Analysis and Visualization with Snowflake Notebooks

## Overview

In this part, we use Snowflake Notebooks to interactively analyze and visualize the data from the Dynamic Tables created in Part 2. We retrieve data with SQL and create charts with Python (Plotly).

## Prerequisites

- Part 2 is complete and data exists in the following Dynamic Tables:
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE`

---

## Step 1: Creating the Notebook

We use a Workspace Notebook (.ipynb).

1. In Snowsight, navigate to **Projects → Workspaces**
2. Open your Workspace
3. Click **+ Add new → Upload file**
4. Upload the provided `ServiceNow_Analysis.ipynb` file
5. Click the uploaded file to open it
6. In the connection dialog, select **Database**: `SERVICENOW_HANDSON`, **Schema**: `ANALYTICS`, **Warehouse**: `COMPUTE_WH`

> **Note**: The `cellN.to_pandas()` pattern (Legacy Notebook) does not work in Workspace Notebooks. Use `session.sql("SELECT ...").to_pandas()` in Python cells to retrieve data.

---

## Step 2: Environment Setup (Python Cell)

```python
# Cell 1: Import libraries and get session
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pandas as pd
from snowflake.snowpark.context import get_active_session

session = get_active_session()
```

> **Tip**: Use `get_active_session()` to obtain a Snowpark session. In all subsequent Python cells, use `session.sql()` to retrieve data.

---

## Step 3: Monthly Incident Trend

```python
# Cell 2: Visualize monthly incident trend
df_monthly = session.sql("""
SELECT
    DATE_TRUNC('month', opened_at)::DATE AS month,
    COUNT(*) AS incident_count,
    COUNT(CASE WHEN priority IN ('1', '2') THEN 1 END) AS high_priority_count,
    ROUND(AVG(mttr_hours), 2) AS avg_mttr_hours
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
WHERE opened_at IS NOT NULL
GROUP BY DATE_TRUNC('month', opened_at)::DATE
ORDER BY month
""").to_pandas()

fig = make_subplots(specs=[[{"secondary_y": True}]])

fig.add_trace(
    go.Bar(x=df_monthly['MONTH'], y=df_monthly['INCIDENT_COUNT'],
           name='Total Incidents', marker_color='#29B5E8'),
    secondary_y=False,
)

fig.add_trace(
    go.Scatter(x=df_monthly['MONTH'], y=df_monthly['AVG_MTTR_HOURS'],
               name='Avg MTTR (hours)', line=dict(color='#FF6F61', width=3)),
    secondary_y=True,
)

fig.update_layout(
    title='Monthly Incident Trend and Average Resolution Time',
    xaxis_title='Month',
    height=500,
    template='plotly_white'
)
fig.update_yaxes(title_text='Incident Count', secondary_y=False)
fig.update_yaxes(title_text='Avg MTTR (hours)', secondary_y=True)

fig.show()
```

---

## Step 4: MTTR Comparison by Category

```python
# Cell 3: MTTR comparison by category (horizontal bar chart)
df_category = session.sql("""
SELECT category, COUNT(*) AS incident_count,
    ROUND(AVG(mttr_hours), 2) AS avg_mttr_hours,
    ROUND(MIN(mttr_hours), 2) AS min_mttr_hours,
    ROUND(MAX(mttr_hours), 2) AS max_mttr_hours
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
WHERE mttr_hours IS NOT NULL AND category IS NOT NULL AND category != ''
GROUP BY category
ORDER BY avg_mttr_hours DESC
""").to_pandas()

fig = go.Figure()
fig.add_trace(go.Bar(
    y=df_category['CATEGORY'], x=df_category['AVG_MTTR_HOURS'],
    name='Avg MTTR', orientation='h', marker_color='#29B5E8',
    text=df_category['AVG_MTTR_HOURS'], textposition='outside'
))
fig.update_layout(
    title='Average MTTR by Category (hours)',
    xaxis_title='MTTR (hours)', yaxis_title='Category',
    height=400, template='plotly_white'
)
fig.show()
```

---

## Step 5: SLA Compliance Rate by Priority

```python
# Cell 4: SLA compliance rate by priority (donut chart + bar chart)
df_sla = session.sql("""
SELECT priority_label, COUNT(*) AS total,
    COUNT(CASE WHEN sla_met = TRUE THEN 1 END) AS met_count,
    COUNT(CASE WHEN sla_met = FALSE THEN 1 END) AS missed_count,
    ROUND(COUNT(CASE WHEN sla_met = TRUE THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN sla_met IS NOT NULL THEN 1 END), 0), 1) AS sla_pct
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
WHERE sla_met IS NOT NULL
GROUP BY priority_label
ORDER BY priority_label
""").to_pandas()

fig = make_subplots(rows=1, cols=2, specs=[[{"type": "pie"}, {"type": "bar"}]],
    subplot_titles=['SLA Compliance Rate (Overall)', 'SLA Compliance Rate by Priority'])

total_met = df_sla['MET_COUNT'].sum()
total_missed = df_sla['MISSED_COUNT'].sum()

fig.add_trace(go.Pie(labels=['SLA Met', 'SLA Missed'], values=[total_met, total_missed],
    hole=0.5, marker_colors=['#29B5E8', '#FF6F61'], textinfo='label+percent'), row=1, col=1)
fig.add_trace(go.Bar(x=df_sla['PRIORITY_LABEL'], y=df_sla['SLA_PCT'],
    marker_color='#29B5E8', text=df_sla['SLA_PCT'].apply(lambda x: f'{x}%'),
    textposition='outside'), row=1, col=2)

fig.update_layout(title='SLA Compliance Analysis', height=450, showlegend=False, template='plotly_white')
fig.show()
```

---

## Step 6: SLA Stage Analysis

```python
# Cell 5: SLA stage analysis
df_stage = session.sql("""
SELECT stage, COUNT(*) AS record_count,
    COUNT(CASE WHEN has_breached = TRUE THEN 1 END) AS breached_count,
    ROUND(AVG(percentage), 2) AS avg_percentage
FROM SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
GROUP BY stage
ORDER BY record_count DESC
""").to_pandas()

fig = make_subplots(rows=1, cols=2, specs=[[{"type": "pie"}, {"type": "bar"}]],
    subplot_titles=['SLA Stage Distribution', 'SLA Breaches by Stage'])

fig.add_trace(go.Pie(labels=df_stage['STAGE'], values=df_stage['RECORD_COUNT'],
    textinfo='label+percent', marker_colors=px.colors.qualitative.Set2), row=1, col=1)
fig.add_trace(go.Bar(x=df_stage['STAGE'], y=df_stage['BREACHED_COUNT'],
    marker_color='#FF6F61', text=df_stage['BREACHED_COUNT'], textposition='outside'), row=1, col=2)

fig.update_layout(title='SLA Stage Analysis (task_sla table)', height=450,
    showlegend=False, template='plotly_white')
fig.show()
```

---

## Step 7: Day of Week x Hour Heatmap

```python
# Cell 6: Day of week x hour heatmap
df_heatmap = session.sql("""
SELECT DAYOFWEEK(opened_at) AS dow_num, DAYNAME(opened_at) AS day_of_week,
    HOUR(opened_at) AS hour_of_day, COUNT(*) AS incident_count
FROM SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED
WHERE opened_at IS NOT NULL
GROUP BY DAYOFWEEK(opened_at), DAYNAME(opened_at), HOUR(opened_at)
ORDER BY dow_num, hour_of_day
""").to_pandas()

pivot = df_heatmap.pivot_table(index='DAY_OF_WEEK', columns='HOUR_OF_DAY',
    values='INCIDENT_COUNT', fill_value=0)
day_order = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
pivot = pivot.reindex([d for d in day_order if d in pivot.index])

fig = go.Figure(data=go.Heatmap(z=pivot.values,
    x=[f'{h}:00' for h in pivot.columns], y=pivot.index,
    colorscale='Blues', text=pivot.values, texttemplate='%{text}'))
fig.update_layout(title='Incident Occurrence Heatmap by Day of Week x Hour',
    xaxis_title='Hour', yaxis_title='Day of Week', height=400, template='plotly_white')
fig.show()
```

---

## Step 8: Team Performance Summary

```python
# Cell 7: Team performance (bubble chart)
df_team = session.sql("""
SELECT assignment_group, total_incidents, resolved_incidents, open_incidents,
    avg_mttr_hours, sla_compliance_pct, top_category
FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
ORDER BY total_incidents DESC
""").to_pandas()

fig = px.scatter(df_team, x='AVG_MTTR_HOURS', y='SLA_COMPLIANCE_PCT',
    size='TOTAL_INCIDENTS', color='ASSIGNMENT_GROUP',
    hover_data=['RESOLVED_INCIDENTS', 'OPEN_INCIDENTS', 'TOP_CATEGORY'],
    title='Team Performance (MTTR vs SLA Compliance)',
    labels={'AVG_MTTR_HOURS': 'Avg MTTR (hours)', 'SLA_COMPLIANCE_PCT': 'SLA Compliance (%)',
            'TOTAL_INCIDENTS': 'Total Incidents', 'ASSIGNMENT_GROUP': 'Team'})
fig.update_layout(height=600, template='plotly_white')
fig.show()
```

---

## Summary

What was accomplished in this part:

1. Created a Workspace Notebook (.ipynb) and set up a Python + SQL analysis environment
2. Performed the following 6 analyses and visualizations:
   - **Monthly Incident Trend**: Combined bar chart + line chart
   - **MTTR by Category**: Horizontal bar chart
   - **SLA Compliance by Priority**: Donut chart + bar chart
   - **SLA Stage Analysis**: Pie chart + bar chart from task_sla data
   - **Day of Week x Hour Heatmap**: Understanding incident occurrence patterns
   - **Team Performance**: Bubble chart showing MTTR, SLA, and incident counts at a glance

> **Tip**: In Workspace Notebooks, retrieve data with `session.sql("SELECT ...").to_pandas()` and visualize with Python. SQL and Python can be seamlessly used together within the same Notebook.

**Next Part**: Proceed to [Part 4: Semantic View + Cortex Analyst Setup](part4_semantic_view.md).
