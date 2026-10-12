# Part 5: AI エージェントアプリ（Cortex Agent + Streamlit）構築

## 概要

このパートでは、Part 4 で作成した Semantic View（データ分析機能）とインシデント履歴の全文検索機能を統合した AI エージェントを構築し、Streamlit in Snowflake でダッシュボード + チャット UI を提供します。

## 前提条件

- Part 4 が完了し、Semantic View が作成済み

## アーキテクチャ

```
┌───────────────────────────────────────────────────┐
│  Streamlit in Snowflake（IT_OPS_AGENT_APP）       │
│  ┌──────────────────┬──────────────────────────┐  │
│  │ 📊 ダッシュボード │ 🤖 AI チャット           │  │
│  │ KPI カード       │ 自然言語で質問            │  │
│  │ 月次推移         │ エージェントが回答        │  │
│  │ カテゴリ別分析   │ 処理ステップ表示          │  │
│  │ チーム別一覧     │                           │  │
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

## Step 1: Cortex Search Service の作成

インシデント履歴を全文検索できるようにするため、Cortex Search Service を作成します。

### 1.1 検索用ビューの作成

```sql
-- =============================================
-- Step 1.1: 検索用ビューの作成
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

### 1.2 Cortex Search Service の作成

```sql
-- =============================================
-- Step 1.2: Cortex Search Service の作成
-- =============================================
CREATE OR REPLACE CORTEX SEARCH SERVICE SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE
  ON search_text
  ATTRIBUTES incident_number, category, priority_label
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'インシデント履歴の全文検索サービス'
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

> **解説**:
> - `ON search_text`: 検索対象のテキストカラムを指定（概要説明 + 詳細説明を結合）
> - `ATTRIBUTES`: フィルタリングや結果表示に使うメタデータカラム
> - `TARGET_LAG`: ソースデータ更新後のリフレッシュ遅延（1 時間）

---

## Step 2: Cortex Agent の作成

Semantic View（データ分析）と Cortex Search Service（インシデント検索）を統合した AI エージェントを作成します。

```sql
-- =============================================
-- Step 2: Cortex Agent の作成
-- =============================================
CREATE OR REPLACE AGENT SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT
  COMMENT = 'IT運用支援AIエージェント - データ分析とインシデント検索を統合'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    response: "あなたはIT運用支援AIアシスタントです。日本語で回答してください。データ分析の結果には具体的な数値を含めてください。インシデント検索の結果にはインシデント番号を含めてください。"
    orchestration: "定量的な分析（MTTR、SLA遵守率、件数、イベントログ分析など）にはAnalystツールを使用してください。過去のインシデントの詳細検索や類似インシデントの検索にはSearchツールを使用してください。イベントログ（IT_EVENT_LOGS）には5000万件のITインフライベントが含まれています。イベントとインシデントの相関分析にはDT_EVENT_INCIDENT_CORRELATIONを活用してください。"
    sample_questions:
      - question: "カテゴリ別のMTTRを教えて"
      - question: "SLA違反の件数は？"
      - question: "ネットワーク関連のインシデントを検索して"
      - question: "イベントログの総件数は？"
      - question: "カテゴリ別のイベント数とインシデント数の比較は？"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Analyst"
        description: "ServiceNowインシデントデータおよびITインフラ イベントログの定量分析（MTTR、SLA遵守率、チーム別パフォーマンス、イベントログ集計、イベント×インシデント相関分析等）"
    - tool_spec:
        type: "cortex_search"
        name: "IncidentSearch"
        description: "過去のインシデント履歴を全文検索（障害内容、対応策、類似インシデント等）"

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

> **解説**:
> - `models.orchestration: auto`: Snowflake が最適な LLM を自動選択
> - `instructions.response`: エージェントの応答スタイルを定義（日本語対応）
> - `instructions.orchestration`: ツールの使い分けルールを定義
> - `execution_environment`: Analyst ツールが SQL を実行するウェアハウスを指定（**必須**）
> - `tools`: エージェントが使える 2 つのツールを指定
>   - `cortex_analyst_text_to_sql`: Semantic View 経由でデータ分析
>   - `cortex_search`: インシデント履歴の全文検索

---

## Step 3: Agent のテスト

### 3.1 Snowsight でのテスト

1. Snowsight にログイン
2. 左メニューから **AI & ML > Agents** を選択
3. `IT_OPS_AGENT` を選択
4. プレイグラウンドで以下のシナリオをテスト

### 3.2 SQL でのテスト

```sql
-- =============================================
-- Step 3: Agent のテスト
-- =============================================
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "カテゴリ別のMTTRを教えて"}]}]}',
  TRUE
);
```

### テストシナリオ

| シナリオ | 入力 | 期待動作 |
|---|---|---|
| データ分析 | 「カテゴリ別の平均MTTRを教えてください」 | Analyst ツールで SQL 生成・実行し数値で回答 |
| インシデント検索 | 「VPN に接続できないインシデントは？」 | Search ツールでインシデント番号付きで回答 |
| 複合質問 | 「ネットワーク関連の傾向と過去の対応は？」 | Analyst + Search の両方を使って回答 |

---

## Step 4: Streamlit in Snowflake でアプリ作成

AI エージェントをダッシュボード付きの Web アプリとして公開します。

### 4.1 ステージの作成

```sql
-- =============================================
-- Step 4.1: Streamlit 用ステージの作成
-- =============================================
CREATE STAGE IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Streamlit アプリ用ステージ';
```

### 4.2 Python ファイルのアップロード

Snowsight の SQL ワークシートで以下を実行します（ファイルパスは適宜変更してください）：

```sql
-- =============================================
-- Step 4.2: Python ファイルのアップロード
-- =============================================
PUT 'file:///path/to/streamlit_app.py'
  @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE/
  AUTO_COMPRESS = FALSE
  OVERWRITE = TRUE;
```

> **注意**: `PUT` コマンドは SQL ワークシートから実行できます。ファイルはローカル PC からアップロードされます。

### 4.3 Streamlit アプリの作成

```sql
-- =============================================
-- Step 4.3: Streamlit アプリの作成
-- =============================================
CREATE OR REPLACE STREAMLIT SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP
  ROOT_LOCATION = '@SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH'
  TITLE = 'IT運用支援AIエージェント'
  COMMENT = 'ServiceNow IT運用データのダッシュボード＋Cortex Agentチャット';
```

### 4.4 アプリの確認

1. Snowsight 左メニューから **Streamlit** を選択
2. `IT_OPS_AGENT_APP` をクリック
3. 2 つのタブを確認：
   - **📊 ダッシュボード**: KPI カード、月次推移、カテゴリ別・優先度別分析、チーム別パフォーマンス
   - **🤖 AI チャット**: Cortex Agent との対話（サンプル質問ボタン付き）

> **ポイント**: Streamlit in Snowflake は SQL だけでデプロイできるため、ローカル環境やCLI は不要です。ハンズオン参加者はブラウザだけで完結します。

---

## Step 5: （参考）Snowflake CoWork への接続

エージェントを Snowflake CoWork（Snowflake Intelligence）に接続すると、Streamlit アプリとは別に、組織内のユーザーがチャット形式で利用できます。

1. Snowsight 左メニューから **AI & ML > Agents** を選択
2. `IT_OPS_AGENT` を選択
3. **Connect to CoWork** ボタンをクリック
4. 表示名やアイコンを設定して接続

---

## Step 6: （参考）クリーンアップ

ハンズオン終了後にリソースを削除する場合：

```sql
-- =============================================
-- Step 6: クリーンアップ（必要な場合のみ）
-- =============================================
USE ROLE ACCOUNTADMIN;

-- Streamlit アプリの削除
DROP STREAMLIT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP;
DROP STAGE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- Cortex Agent の削除
DROP AGENT IF EXISTS SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT;

-- Cortex Search Service の削除
DROP CORTEX SEARCH SERVICE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.INCIDENT_SEARCH_SERVICE;

-- 検索用ビューの削除
DROP VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.V_INCIDENT_SEARCH;

-- Semantic View の削除
DROP SEMANTIC VIEW IF EXISTS SERVICENOW_HANDSON.ANALYTICS.SERVICENOW_SEMANTIC_VIEW;

-- Dynamic Tables の削除
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_ENRICHED;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_INCIDENT_DAILY_STATS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_SLA_ANALYSIS;
DROP DYNAMIC TABLE IF EXISTS SERVICENOW_HANDSON.ANALYTICS.DT_TEAM_PERFORMANCE;

-- ハンズオン用データベースの削除
DROP DATABASE IF EXISTS SERVICENOW_HANDSON;

-- Connector の一時停止
USE APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
CALL PAUSE_CONNECTOR();
```

---

## まとめ

このパートで実施したこと：

1. **Cortex Search Service** を作成（インシデント履歴の全文検索機能）
2. **Cortex Agent** を作成（Analyst + Search を統合した AI エージェント）
3. **テスト** を実施（データ分析、インシデント検索、複合質問）
4. **Streamlit in Snowflake** でダッシュボード + AI チャットアプリを構築

---

## ハンズオン全体の振り返り

5 つのパートを通じて、以下の Snowflake 機能をエンドツーエンドで体験しました：

| パート | 機能 | 成果物 |
|---|---|---|
| Part 1 | Snowflake Connector for ServiceNow（OAuth2） | ServiceNow データの安全な自動同期 |
| Part 2 | Dynamic Tables | 宣言的データ変換パイプライン |
| Part 3 | Snowflake Notebooks | インタラクティブな分析・可視化 |
| Part 4 | Semantic View + Cortex Analyst | 自然言語データ分析 |
| Part 5 | Cortex Agent + Streamlit in Snowflake | AI エージェントアプリ（ダッシュボード + チャット） |

**ポイント**: ServiceNow からの安全なデータ取り込み（OAuth2 認証）から AI エージェントアプリまで、すべて Snowflake 上で完結しています。ローカル環境やサードパーティツールは一切不要です。
