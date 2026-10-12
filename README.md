# ServiceNow x Snowflake ハンズオン

## IT運用インテリジェンス基盤の構築

ServiceNow のデータを Snowflake に取り込み、データ加工・分析・可視化・AI エージェントアプリまでをエンドツーエンドで構築するハンズオンです。

---

## アーキテクチャ全体図

```
ServiceNow PDI
  │
  │ Snowflake Connector for ServiceNow
  │ （OAuth 2.0 認証・自動同期）
  ▼
┌──────────────────────────────────────────────────────┐
│                    Snowflake                          │
│                                                       │
│  ┌─────────────────────────┐ ┌───────────────────┐  │
│  │ Raw Data (Connector)    │ │ S3 External Stage │  │
│  │ incident, sys_user,     │ │ IT Event Logs     │  │
│  │ sys_user_group, task_sla│ │ (500万行)          │  │
│  └─────────────┬───────────┘ └────────┬──────────┘  │
│                │                      │              │
│                ▼                      ▼              │
│  ┌─────────────────────────────────────────────────┐  │
│  │ Dynamic Tables (分析用パイプライン)              │  │
│  │  DT_INCIDENT_ENRICHED（JOIN: 3テーブル）        │  │
│  │  DT_INCIDENT_DAILY_STATS（日別集計）            │  │
│  │  DT_SLA_ANALYSIS（SLA分析）                     │  │
│  │  DT_TEAM_PERFORMANCE（チーム別集計）            │  │
│  │  DT_EVENT_INCIDENT_CORRELATION（突合分析）      │  │
│  └──────┬──────────────────┬───────────────────────┘  │
│         │                  │                           │
│         ▼                  ▼                           │
│  ┌─────────────┐  ┌──────────────────┐                │
│  │ Notebooks   │  │ Semantic View    │                │
│  │ (分析/可視化)│  │ + Cortex Analyst │                │
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
│                   │ (ダッシュボード   │                 │
│                   │  + AIチャット)   │                 │
│                   └──────────────────┘                 │
└──────────────────────────────────────────────────────┘
```

---

## ハンズオン構成

| パート | 内容 | 使用するSnowflake機能 | 手順書 |
|---|---|---|---|
| **Part 1** | データロード | Snowflake Connector for ServiceNow | [part1_data_loading.md](part1_data_loading.md) |
| **Part 1.5** | 外部データロード | S3 External Stage, COPY INTO, ウェアハウスサイズ比較 | [part1_5_s3_data_loading.md](part1_5_s3_data_loading.md) |
| **Part 2** | データ加工 | Dynamic Tables | [part2_dynamic_tables.md](part2_dynamic_tables.md) |
| **Part 3** | 分析・可視化 | Snowflake Notebooks (SQL + Python) | [part3_analysis_notebook.md](part3_analysis_notebook.md) |
| **Part 4** | 自然言語分析 | Semantic View, Cortex Analyst | [part4_semantic_view.md](part4_semantic_view.md) |
| **Part 5** | AIエージェントアプリ | Cortex Agent, Cortex Search, Streamlit in Snowflake | [part5_ai_agent_app.md](part5_ai_agent_app.md) |

---

## 前提条件

### Snowflake
- Snowflake アカウント（ACCOUNTADMIN ロール）
- Snowflake Connector for ServiceNow がインストール済み
  - Snowflake Marketplace から「Snowflake Connector for ServiceNow」を取得・インストール

### ServiceNow
- ServiceNow Developer Program アカウント
- PDI（Personal Developer Instance）
  - [developer.servicenow.com](https://developer.servicenow.com/) で無料で作成可能

> **ローカル環境は不要です。** すべてのステップは Snowsight（Snowflake の Web UI）上で完結します。

---

## 使用する ServiceNow テーブル

| テーブル名 | 説明 | 用途 | ServiceNow での確認方法 |
|---|---|---|---|
| `incident` | インシデント管理 | メインの分析対象 | Incident > All |
| `sys_user` | ユーザー情報 | 担当者情報の結合 | User Administration > Users |
| `sys_user_group` | ユーザーグループ | チーム情報の結合 | User Administration > Groups |
| `task_sla` | SLA 達成状況 | SLA 分析 | （システムテーブル — Snowflake 側で確認） |

---

## 作成する Snowflake オブジェクト一覧

| オブジェクト | 種類 | 説明 |
|---|---|---|
| `SERVICENOW_DEST_DB.SERVICENOW_DATA` | Schema | Connector の同期先 |
| `SERVICENOW_HANDSON.ANALYTICS` | Schema | 分析用 |
| `DT_INCIDENT_ENRICHED` | Dynamic Table | インシデント詳細（JOIN: incident + sys_user + sys_user_group） |
| `DT_INCIDENT_DAILY_STATS` | Dynamic Table | 日別インシデント統計 |
| `DT_SLA_ANALYSIS` | Dynamic Table | SLA 達成状況分析（JOIN: task_sla + incident） |
| `DT_TEAM_PERFORMANCE` | Dynamic Table | チーム別パフォーマンス |
| `IT_EVENT_LOGS` | Table | S3 からロードした IT イベントログ（5,000万行×10ファイル） |
| `DT_EVENT_INCIDENT_CORRELATION` | Dynamic Table | イベントログ × インシデント突合分析 |
| `S3_EVENT_STAGE` | External Stage | S3 バケットへの接続 |
| `SERVICENOW_SEMANTIC_VIEW` | Semantic View | 自然言語分析用のメタデータ定義（6テーブル: インシデント+イベントログ） |
| `INCIDENT_SEARCH_SERVICE` | Cortex Search Service | インシデント履歴の全文検索 |
| `IT_OPS_AGENT` | Cortex Agent | AI エージェント（Analyst + Search、イベントログ分析対応） |
| `IT_OPS_AGENT_APP` | Streamlit in Snowflake | ダッシュボード + AI チャット UI |

---

## お客様への訴求ポイント

1. **ノーコード連携**: ServiceNow Connector でデータ取り込みを自動化。API 開発やバッチ処理は不要
2. **宣言的パイプライン**: Dynamic Tables で SQL を書くだけ。スケジュール管理やエラーハンドリングは Snowflake が自動実行
3. **AI 活用の容易さ**: Semantic View を定義するだけで自然言語分析が可能。AI/ML の専門知識は不要
4. **エンドツーエンド**: データ取り込みから AI アプリまで Snowflake 上で完結。追加のインフラ不要
5. **ガバナンス**: すべてのデータが Snowflake 内に集約され、ロールベースのアクセス制御を適用可能
6. **スケーラビリティ**: ウェアハウスサイズを変更するだけでパフォーマンスが向上。SQL やインフラの変更は不要
