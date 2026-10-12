# Part 1: ServiceNow Connector 設定とデータロード

## 概要

このパートでは、ServiceNow の個人開発インスタンス (PDI) を用意し、**OAuth2 Client Credentials** 認証を使って Snowflake Connector for ServiceNow でデータを安全に同期します。

## 前提条件

- Snowflake アカウント（ACCOUNTADMIN ロール）
- Snowflake Connector for ServiceNow がインストール済み（Snowsight の **Data Products → Connectors** から入手可能）

---

## Step 1: ServiceNow 個人開発インスタンス (PDI) の作成

### 1.1 ServiceNow Developer Program への登録

1. [ServiceNow Developer サイト](https://developer.servicenow.com/) にアクセス
2. **Sign up** をクリックし、アカウントを作成（メールアドレス、パスワード等を入力）
3. メール認証を完了してログイン

### 1.2 PDI（Personal Developer Instance）の作成

1. ログイン後、ダッシュボードから **Request Instance** をクリック
2. インスタンスタイプを選択（最新リリースを推奨）
3. 数分でインスタンスが作成され、以下の情報が表示されます：
   - **Instance URL**: `https://<your-instance>.service-now.com`
   - **Username**: `admin`
   - **Password**: ダッシュボードの Instance 管理ページに表示

> **注意**: PDI に SSO でログインしている場合、`admin` のパスワードは developer.servicenow.com のダッシュボードで確認できます。「Manage instance password」のリンクからパスワードをリセットすることも可能です。

### 1.3 PDI のデモデータ確認

PDI には ITSM（IT Service Management）のデモデータがプリロードされています。以下のテーブルを今回使用します：

| テーブル | 説明 | 件数目安 |
|---|---|---|
| `incident` | インシデント（障害報告） | 数十件 |
| `sys_user` | システムユーザー | 数百件 |
| `sys_user_group` | ユーザーグループ | 数十件 |
| `task_sla` | タスクSLA達成状況 | 数十件 |

---

## Step 2: ServiceNow 側の OAuth2 設定

本番環境を見据えて、**OAuth2 Client Credentials** 認証を設定します。Basic 認証（ID/パスワード）ではなく、OAuth2 を使うことでセキュリティ要件を満たします。

### 2.1 Client Credentials Grant Type の有効化

ServiceNow ではデフォルトで Client Credentials Grant Type が無効になっているため、システムプロパティを作成して有効化します。

1. ブラウザのアドレスバーに以下の URL を直接入力してアクセス：
   ```
   https://<your-instance>.service-now.com/sys_properties_list.do?sysparm_query=name=glide.oauth.inbound.client.credential.grant_type.enabled
   ```

2. 「No records to display」と表示される場合、右上の **New** ボタンをクリック

3. 以下を入力して **Submit**：
   - **Name**: `glide.oauth.inbound.client.credential.grant_type.enabled`
   - **Type**: `true | false`
   - **Value**: `true`

> **注意**: ServiceNow の Next Experience UI（Polaris）では、ナビゲーションフィルターで `sys_properties` を検索しても結果が出ません。URL を直接入力してアクセスしてください。

### 2.2 OAuth アプリケーションの作成

1. ブラウザのアドレスバーに以下の URL を直接入力：
   ```
   https://<your-instance>.service-now.com/oauth_entity_list.do
   ```

2. **New** をクリック

3. 以下を入力：
   - **Name**: `Snowflake Connector`（任意の名前）
   - **Accessible from**: `All application scopes`
   - **Active**: チェック

4. **Submit** をクリック

5. 作成されたレコードを再度開き、自動生成された **Client ID** と **Client Secret** をメモ

> **重要**: Client Secret は一度しか表示されない場合があります。必ずこの時点でメモしてください。

### 2.3 OAuth Application User の設定

OAuth2 Client Credentials で認証した際に、どのユーザーとして API にアクセスするかを設定します。

1. 先ほど作成した「Snowflake Connector」のレコードを開く

2. **OAuth Application User** フィールドが表示されていない場合：
   - 画面左上のハンバーガーメニュー（≡）→ **Configure → Form Builder** を開く
   - 左側のフィールド一覧で `OAuth Application User` を検索
   - フォーム上にドラッグ＆ドロップで追加し、右上の **Save** をクリック
   - Form Builder を閉じてレコード画面に戻る

3. **OAuth Application User** フィールドの虫眼鏡アイコンをクリックし、**System Administrator**（admin）を選択

4. **Scope Restriction** を **Broadly scoped** に変更

5. **Update** をクリック

> **注意**: Scope Restriction が `Securely scoped` のままだと、`Access to unscoped api is not allowed` エラーが発生します。必ず `Broadly scoped` に変更してください。

---

## Step 3: Snowflake 側の事前準備

Snowsight の SQL ワークシートで以下を実行します。

### 3.1 ハンズオン用オブジェクトの作成

```sql
-- =============================================
-- Step 3.1: ハンズオン用オブジェクトの作成
-- =============================================
USE ROLE ACCOUNTADMIN;

-- Connector のデータ保存先データベース・スキーマ
CREATE DATABASE IF NOT EXISTS SERVICENOW_DEST_DB;
CREATE SCHEMA IF NOT EXISTS SERVICENOW_DEST_DB.DEST_SCHEMA;
```

### 3.2 Connector への権限付与

```sql
-- =============================================
-- Step 3.2: Connector アプリケーションへの権限付与
-- =============================================
GRANT EXECUTE TASK ON ACCOUNT TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

GRANT USAGE ON DATABASE SERVICENOW_DEST_DB TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT USAGE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT CREATE TABLE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
GRANT CREATE VIEW ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;

-- 同期先スキーマの所有権を Connector に移譲（再セットアップ時のスキーマ競合を防止）
CALL system$grant_ownership_to_application('SNOWFLAKE_CONNECTOR_FOR_SERVICENOW', true, 'SERVICENOW_DEST_DB', 'DEST_SCHEMA');
```

> **解説**: Connector アプリケーションが同期タスクの実行、ウェアハウスの使用、同期先スキーマへのテーブル・ビュー作成を行うための権限を付与します。認証関連のオブジェクト（Security Integration、Secret、Network Rule、External Access Integration）は、次の Step 4 のウィザードで Connector が自動的に作成するため、手動で作成する必要はありません。



---

## Step 4: Connector の設定（UI ウィザード）

Snowsight の UI ウィザードを使って Connector を設定します。

### 4.1 ウィザードを開く

1. Snowsight で **Data Products → Connectors** に移動
2. **Snowflake Connector for ServiceNow** をクリック
3. **Wizard** タブを開く

### 4.2 Prerequisites（前提条件）

画面の指示に従い、ウェアハウスと宛先データベース/スキーマを確認して次へ進みます。

### 4.3 Configure（構成）

- **Warehouse**: `COMPUTE_WH`
- **Destination Database**: `SERVICENOW_DEST_DB`
- **Destination Schema**: `DEST_SCHEMA`
- **Role**: `ACCOUNTADMIN`（Select existing から選択。同期データへの読み取りアクセスを持つロール）

> **トラブルシューティング**: 「Selected schema is in use by the other connector instance」エラーが出る場合：
> 再インストール時に同じスキーマを再利用するには、**finalize 前に**以下を SQL ワークシートで実行してからウィザードを再試行してください：
> ```sql
> -- オーナーシップを新しい Connector インスタンスに移管
> GRANT USAGE ON DATABASE SERVICENOW_DEST_DB TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
> GRANT USAGE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
> GRANT CREATE TABLE ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
> GRANT CREATE VIEW ON SCHEMA SERVICENOW_DEST_DB.DEST_SCHEMA TO APPLICATION SNOWFLAKE_CONNECTOR_FOR_SERVICENOW;
> CALL system$grant_ownership_to_application('SNOWFLAKE_CONNECTOR_FOR_SERVICENOW', true, 'SERVICENOW_DEST_DB', 'DEST_SCHEMA');
> ```
> ※ クリーンアップ時に `GRANT OWNERSHIP ON ALL TABLES/VIEWS ... TO ROLE ACCOUNTADMIN` でオーナーシップを移管してからアンインストールすることで、この手順が有効になります。詳細は `sql/cleanup.sql` を参照。

### 4.4 Authentication（認証）

1. 認証方式で **OAuth2 Client Credentials [Recommended]** を選択
2. 以下を入力：
   - **ServiceNow Instance**: `<your-instance>`（`dev12345` の部分のみ）
   - **Client ID**: Step 2.2 でメモした Client ID
   - **Client Secret**: Step 2.2 でメモした Client Secret
3. **Connect** をクリック

> **トラブルシューティング**: `access_denied` エラーが出る場合は、Step 2.1 のシステムプロパティ作成と Step 2.3 の Scope Restriction 設定を再確認してください。

### 4.5 Validate source（ソース検証）

- **Journal Table** に `sys_audit_delete` が表示されるので、そのまま **Validate** をクリック

---

## Step 5: テーブル同期の開始

### 5.1 同期テーブルの選択

Validate が成功すると、テーブル選択画面に進みます。

1. **Edit tables** をクリック
2. 以下の 4 テーブルを検索して追加：
   - `incident`
   - `sys_user`
   - `sys_user_group`
   - `task_sla`
3. **Sync Every** はデフォルトの `1 hour` のまま
4. テーブルを有効化

> **解説**: PDI にはこれらのテーブルにデモデータがプリロードされています。インシデント管理、ユーザー管理、SLA 追跡に必要なデータが揃います。

### 5.2 同期完了の確認

同期が開始されると、各テーブルのステータスが「Syncing data」と表示されます。初期同期は数分で完了します。

```sql
-- =============================================
-- Step 5.2: 同期データの行数確認
-- =============================================
SELECT 'INCIDENT' AS table_name, COUNT(*) AS row_count FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
UNION ALL
SELECT 'SYS_USER', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER
UNION ALL
SELECT 'SYS_USER_GROUP', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.SYS_USER_GROUP
UNION ALL
SELECT 'TASK_SLA', COUNT(*) FROM SERVICENOW_DEST_DB.DEST_SCHEMA.TASK_SLA;
```

期待される結果（PDI のデモデータ量により多少異なります）：

| テーブル | 件数目安 |
|---|---|
| INCIDENT | 60〜70件 |
| SYS_USER | 600〜650件 |
| SYS_USER_GROUP | 50〜55件 |
| TASK_SLA | 10〜20件 |

### 5.3 データのサンプル確認

```sql
-- =============================================
-- Step 5.3: インシデントデータの確認
-- =============================================
SELECT
    NUMBER,
    SHORT_DESCRIPTION,
    PRIORITY,
    STATE,
    CATEGORY,
    ASSIGNED_TO,
    SYS_CREATED_ON,
    CLOSED_AT
FROM SERVICENOW_DEST_DB.DEST_SCHEMA.INCIDENT
LIMIT 10;
```

> **解説**: Connector は各 ServiceNow テーブルに対して以下を作成します：
> - `<TABLE_NAME>`: データテーブル
> - `<TABLE_NAME>__EVENT_LOG`: 変更履歴テーブル

---

## Step 6:（参考）Connector の一時停止

ハンズオンの全パートが完了したら、不要なクレジット消費を防ぐために Connector を一時停止します。

Snowsight の **Data Products → Connectors → Snowflake Connector for ServiceNow** を開き、**Data Sync** タブの **Pause Connector** ボタンをクリックします。

> **注意**: Connector を停止しないと、1 時間ごとにウェアハウスが起動しクレジットが消費されます。ハンズオン終了後は必ず停止してください。

---

## まとめ

このパートで実施したこと：

1. ServiceNow PDI（個人開発インスタンス）を作成
2. ServiceNow 側で OAuth2 Client Credentials の設定（システムプロパティ、OAuth アプリケーション、Application User、Scope Restriction）
3. Snowflake 側で同期先データベース・スキーマの作成と Connector への権限付与
4. UI ウィザードで Connector を設定し、OAuth2 Client Credentials で接続
5. 4 つのテーブル（incident, sys_user, sys_user_group, task_sla）の同期を開始・確認

**次のパート**: [Part 2: Dynamic Tables でデータ加工](part2_dynamic_tables.md) に進みます。
