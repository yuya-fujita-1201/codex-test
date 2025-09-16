## オブジェクト定義

### ChatThread__c（カスタムオブジェクト）
- 概要: チャットスレッド。
- 主な項目:
  - `Name`(テキスト): タイトル
  - `Description__c`(テキスト): 説明
  - `Status__c`(ピックリスト): 状態（例: Active）
  - `ExternalThreadId__c`(テキスト): 外部システムのスレッドID
  - `RelatedRecordId__c`(テキスト): 関連レコードID
  - `RelatedObjectType__c`(テキスト): 関連オブジェクト種別

### ChatMessage__c（カスタムオブジェクト）
- 概要: スレッドに属するメッセージ。
- 主な項目:
  - `Body__c`(長テキスト): 本文（最大1000）
  - `Thread__c`(主従): 親スレッド
  - `PostedBy__c`(参照:User): 投稿者ユーザ参照
  - `GNT_PostedBy__c`(テキスト): 投稿者名（画面/API表示用）
  - `PostedAt__c`(日時): 投稿日時
  - `ExternalMessageId__c`(外部ID,一意): 外部メッセージID
  - `SyncStatus__c`(ピックリスト): Pending / Synced / Failed
  - `ErrorMessage__c`(長テキスト): エラー内容
  - `ReplyTo__c`(参照:ChatMessage__c): 返信先

### プラットフォームイベント
- `ChatMessageOut__e`
  - 外部送信用イベント。項目例: `Operation__c`(Text), `MessageId__c`, `ThreadId__c`, `Payload__c`, `Version__c`, `CorrelationKey__c`
- `ChatMessageIn__e`
  - 受信イベント。項目例: `Operation__c`(Text), `ExternalMessageId__c`, `ExternalThreadId__c`, `ThreadId__c`, `Payload__c`, `CorrelationKey__c`
- `ChatSyncAck__e`
  - 同期結果のACK。項目: `MessageId__c`, `ExternalMessageId__c`, `Success__c`, `ErrorMessage__c`, `CorrelationKey__c`

### Named Credential
- `External_Chat`（NoAuthentication, HTTPS エンドポイント）

### 権限セット
- `Custom_Chat_User`
  - オブジェクト/項目権限（スレッド/メッセージ）
  - タブ可視化: `Chat_Workspace`=Visible, `ChatThread__c`/`ChatMessage__c`=Available
