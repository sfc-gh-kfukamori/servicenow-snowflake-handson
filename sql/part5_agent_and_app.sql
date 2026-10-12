-- =============================================================================
-- Part 5: AI エージェントアプリ（Cortex Agent + Streamlit in Snowflake）
-- =============================================================================
-- Semantic View（データ分析）と Cortex Search Service（インシデント検索）を統合した
-- AI エージェントを作成し、Streamlit in Snowflake でダッシュボード+チャットUIを構築します。
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SCHEMA SERVICENOW_HANDSON.ANALYTICS;

-- -----------------------------------------------------------------------------
-- Step 1: Cortex Search Service の作成
-- インシデント履歴の全文検索サービス
-- まずインシデント情報を検索用にまとめたビューを作成し、
-- それを基に Cortex Search Service を構築する
-- -----------------------------------------------------------------------------

-- 検索用ビュー: インシデントの主要情報をテキスト結合して検索可能にする
CREATE OR REPLACE VIEW V_INCIDENT_SEARCH AS
SELECT
    sys_id,
    incident_number,
    category,
    priority_label,
    state_label,
    assignment_group_name,
    -- 検索対象テキスト: 番号、説明、カテゴリ、優先度、状態、担当を結合
    incident_number || ' ' ||
    COALESCE(short_description, '') || ' ' ||
    COALESCE(description, '') || ' ' ||
    COALESCE(category, '') || ' ' ||
    COALESCE(priority_label, '') || ' ' ||
    COALESCE(state_label, '') || ' ' ||
    COALESCE(assignment_group_name, '') || ' ' ||
    COALESCE(assigned_to_name, '')
    AS search_text
FROM DT_INCIDENT_ENRICHED;

-- Cortex Search Service: snowflake-arctic-embed-m-v1.5 で埋め込みベクトルを生成し、
-- セマンティック検索を可能にする
CREATE OR REPLACE CORTEX SEARCH SERVICE INCIDENT_SEARCH_SERVICE
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
  FROM V_INCIDENT_SEARCH
);

-- -----------------------------------------------------------------------------
-- Step 2: Cortex Agent の作成
-- Analyst（Semantic View経由のデータ分析）と Search（インシデント全文検索）を
-- 1つのエージェントに統合。自然言語で質問するだけで適切なツールを自動選択する。
--
-- orchestration: auto → Snowflake が最適な LLM を自動選択
-- execution_environment: Analyst が SQL を実行するウェアハウスを指定（必須）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE AGENT IT_OPS_AGENT
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

-- -----------------------------------------------------------------------------
-- Step 3: Agent のテスト（SQL から実行）
-- DATA_AGENT_RUN の引数: エージェント名、リクエストボディ（$$...$$リテラル）
-- content は [{type: "text", text: "質問文"}] の配列形式で渡す
-- -----------------------------------------------------------------------------
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT',
    $${"messages": [{"role": "user", "content": [{"type": "text", "text": "カテゴリ別のMTTRを教えて"}]}]}$$
  )
):content[2]:text::STRING AS agent_response;

-- -----------------------------------------------------------------------------
-- Step 4: Streamlit in Snowflake のデプロイ
-- streamlit_app.py を内部ステージにアップロードし、STREAMLIT オブジェクトを作成
-- ステージはアプリのソースコード配置場所
-- -----------------------------------------------------------------------------

-- アプリ用の内部ステージを作成
CREATE STAGE IF NOT EXISTS SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE;

-- ローカルの streamlit_app.py をステージにアップロード
-- ※ Snowsight の場合は PUT コマンドではなく UI からアップロード
PUT file://streamlit_app.py @SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE
  AUTO_COMPRESS = FALSE
  OVERWRITE = TRUE;

-- Streamlit アプリの作成
CREATE OR REPLACE STREAMLIT SERVICENOW_HANDSON.ANALYTICS.IT_OPS_AGENT_APP
  ROOT_LOCATION = '@SERVICENOW_HANDSON.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = COMPUTE_WH
  COMMENT = 'ServiceNow IT運用データのダッシュボード＋Cortex Agentチャット';

-- Snowsight 左メニュー > Streamlit から IT_OPS_AGENT_APP をクリックして開く
