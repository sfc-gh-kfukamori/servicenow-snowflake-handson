# Part 3: Snowflake Notebooks で分析・可視化

## 概要

このパートでは、Snowflake Notebooks を使って Part 2 で作成した Dynamic Tables のデータをインタラクティブに分析・可視化します。SQL でデータを取得し、Python（Plotly）でチャートを作成します。

## 前提条件

- Part 2 が完了し、以下の Dynamic Tables にデータが存在：
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS`
  - `SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE`

---

## Step 1: Notebook の作成

Workspace Notebook（.ipynb）を使用します。

1. Snowsight で **Projects → Workspaces** に移動
2. 自分の Workspace を開く
3. **+ Add new → Upload file** をクリック
4. 提供された `ServiceNow_Analysis.ipynb` ファイルをアップロード
5. アップロードしたファイルをクリックして開く
6. 接続ダイアログで **Database**: `SERVICENOW_HANDSON`、**Schema**: `ANALYTICS`、**Warehouse**: `COMPUTE_WH` を選択

> **注意**: `cellN.to_pandas()` パターン（Legacy Notebook）は Workspace Notebook では使えません。Python セル内で `session.sql("SELECT ...").to_pandas()` を使ってデータを取得します。

---

## Step 2: 環境セットアップ（Python セル）

```python
# セル 1: ライブラリのインポートとセッション取得
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pandas as pd
from snowflake.snowpark.context import get_active_session

session = get_active_session()
```

> **ポイント**: `get_active_session()` で Snowpark セッションを取得します。以降のPythonセルではすべて `session.sql()` でデータを取得します。

---

## Step 3: インシデント月次発生トレンド

```python
# セル 2: 月次インシデントトレンドの可視化
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
           name='総インシデント数', marker_color='#29B5E8'),
    secondary_y=False,
)

fig.add_trace(
    go.Scatter(x=df_monthly['MONTH'], y=df_monthly['AVG_MTTR_HOURS'],
               name='平均MTTR（時間）', line=dict(color='#FF6F61', width=3)),
    secondary_y=True,
)

fig.update_layout(
    title='月次インシデント発生トレンドと平均解決時間',
    xaxis_title='月',
    height=500,
    template='plotly_white'
)
fig.update_yaxes(title_text='インシデント数', secondary_y=False)
fig.update_yaxes(title_text='平均MTTR（時間）', secondary_y=True)

fig.show()
```

---

## Step 4: カテゴリ別 MTTR 比較

```python
# セル 3: カテゴリ別MTTR比較（横棒グラフ）
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
    name='平均MTTR', orientation='h', marker_color='#29B5E8',
    text=df_category['AVG_MTTR_HOURS'], textposition='outside'
))
fig.update_layout(
    title='カテゴリ別 平均MTTR 比較（時間）',
    xaxis_title='MTTR（時間）', yaxis_title='カテゴリ',
    height=400, template='plotly_white'
)
fig.show()
```

---

## Step 5: 優先度別 SLA 遵守率

```python
# セル 4: 優先度別SLA遵守率（ドーナツチャート + 棒グラフ）
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
    subplot_titles=['SLA遵守率（全体）', '優先度別SLA遵守率'])

total_met = df_sla['MET_COUNT'].sum()
total_missed = df_sla['MISSED_COUNT'].sum()

fig.add_trace(go.Pie(labels=['SLA遵守', 'SLA未遵守'], values=[total_met, total_missed],
    hole=0.5, marker_colors=['#29B5E8', '#FF6F61'], textinfo='label+percent'), row=1, col=1)
fig.add_trace(go.Bar(x=df_sla['PRIORITY_LABEL'], y=df_sla['SLA_PCT'],
    marker_color='#29B5E8', text=df_sla['SLA_PCT'].apply(lambda x: f'{x}%'),
    textposition='outside'), row=1, col=2)

fig.update_layout(title='SLA 遵守率分析', height=450, showlegend=False, template='plotly_white')
fig.show()
```

---

## Step 6: SLA ステージ別分析

```python
# セル 5: SLAステージ別分析
df_stage = session.sql("""
SELECT stage, COUNT(*) AS record_count,
    COUNT(CASE WHEN has_breached = TRUE THEN 1 END) AS breached_count,
    ROUND(AVG(percentage), 2) AS avg_percentage
FROM SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS
GROUP BY stage
ORDER BY record_count DESC
""").to_pandas()

fig = make_subplots(rows=1, cols=2, specs=[[{"type": "pie"}, {"type": "bar"}]],
    subplot_titles=['SLAステージ分布', 'ステージ別 SLA違反件数'])

fig.add_trace(go.Pie(labels=df_stage['STAGE'], values=df_stage['RECORD_COUNT'],
    textinfo='label+percent', marker_colors=px.colors.qualitative.Set2), row=1, col=1)
fig.add_trace(go.Bar(x=df_stage['STAGE'], y=df_stage['BREACHED_COUNT'],
    marker_color='#FF6F61', text=df_stage['BREACHED_COUNT'], textposition='outside'), row=1, col=2)

fig.update_layout(title='SLA ステージ別分析（task_sla テーブル）', height=450,
    showlegend=False, template='plotly_white')
fig.show()
```

---

## Step 7: 曜日 × 時間帯ヒートマップ

```python
# セル 6: 曜日×時間帯ヒートマップ
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
fig.update_layout(title='曜日 × 時間帯別 インシデント発生ヒートマップ',
    xaxis_title='時間帯', yaxis_title='曜日', height=400, template='plotly_white')
fig.show()
```

---

## Step 8: チーム別パフォーマンスサマリー

```python
# セル 7: チーム別パフォーマンス（バブルチャート）
df_team = session.sql("""
SELECT assignment_group, total_incidents, resolved_incidents, open_incidents,
    avg_mttr_hours, sla_compliance_pct, top_category
FROM SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE
ORDER BY total_incidents DESC
""").to_pandas()

fig = px.scatter(df_team, x='AVG_MTTR_HOURS', y='SLA_COMPLIANCE_PCT',
    size='TOTAL_INCIDENTS', color='ASSIGNMENT_GROUP',
    hover_data=['RESOLVED_INCIDENTS', 'OPEN_INCIDENTS', 'TOP_CATEGORY'],
    title='チーム別パフォーマンス（MTTR vs SLA遵守率）',
    labels={'AVG_MTTR_HOURS': '平均MTTR（時間）', 'SLA_COMPLIANCE_PCT': 'SLA遵守率（%）',
            'TOTAL_INCIDENTS': '総インシデント数', 'ASSIGNMENT_GROUP': 'チーム'})
fig.update_layout(height=600, template='plotly_white')
fig.show()
```

---

## まとめ

このパートで実施したこと：

1. Workspace Notebook（.ipynb）を作成し、Python + SQL の分析環境を構築
2. 以下の 6 つの分析・可視化を実施：
   - **月次インシデント発生トレンド**: 棒グラフ + 折れ線グラフの複合チャート
   - **カテゴリ別 MTTR 比較**: 横棒グラフ
   - **優先度別 SLA 遵守率**: ドーナツチャート + 棒グラフ
   - **SLA ステージ別分析**: task_sla データの円グラフ + 棒グラフ
   - **曜日 × 時間帯ヒートマップ**: インシデント発生パターンの把握
   - **チーム別パフォーマンス**: バブルチャートで MTTR・SLA・件数を一覧

> **ポイント**: Workspace Notebook では `session.sql("SELECT ...").to_pandas()` でデータを取得し、Python で可視化します。SQL と Python を同じ Notebook 内でシームレスに使い分けられます。

**次のパート**: [Part 4: Semantic View + Cortex Analyst 構築](part4_semantic_view.md) に進みます。
