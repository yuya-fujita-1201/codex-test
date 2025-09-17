## オブジェクト定義

### GNT_ChatThread__c（カスタムオブジェクト）
- 概要: チャットスレッド。
- 主な項目:
  - `Name`(テキスト): タイトル
  - `GNT_Status__c`(ピックリスト): 状態（例: Active）
  - `GNT_RelatedRecordId__c`(テキスト): 関連レコードID
  - `GNT_RelatedObjectType__c`(テキスト): 関連オブジェクト種別

### GNT_ChatMessage__c（カスタムオブジェクト）
- 概要: スレッドに属するメッセージ。
- 主な項目:
  - `GNT_Body__c`(長テキスト): 本文（最大1000）
  - `GNT_Thread__c`(主従): 親スレッド
  - `GNT_PostedBy__c`(テキスト): 投稿者名（画面/API表示用）
  - `GNT_PostedAt__c`(日時): 投稿日時
  - `GNT_ExternalMessageId__c`(外部ID,一意): 外部メッセージID
  - `GNT_SyncStatus__c`(ピックリスト): Pending / Synced / Failed
  - `GNT_ErrorMessage__c`(長テキスト): エラー内容
  - `GNT_ReplyTo__c`(参照:GNT_ChatMessage__c): 返信先

### プラットフォームイベント
- `ChatMessageOut__e`
  - 外部送信用イベント。項目例: `Operation__c`(Text), `MessageId__c`, `ThreadId__c`, `Payload__c`, `Version__c`, `CorrelationKey__c`
- `ChatMessageIn__e`
  - 受信イベント。項目例: `Operation__c`(Text), `ExternalMessageId__c`, `ExternalThreadId__c`, `ThreadId__c`, `Payload__c`, `CorrelationKey__c`
- `ChatSyncAck__e`
  - 同期結果のACK。項目: `MessageId__c`, `ExternalMessageId__c`, `Success__c`, `ErrorMessage__c`, `CorrelationKey__c`

### Named Credential
- `GNT_Azure_Chat_NC`（SecuredEndpoint, External Credential `GNT_Azure_EC` 経由で HTTPS エンドポイントへ接続）

### 権限セット
- `GNT_Custom_Chat_User`
  - オブジェクト/項目権限（スレッド/メッセージ）
  - タブ可視化: `GNT_Chat_Workspace`=Visible, `GNT_ChatThread__c`/`GNT_ChatMessage__c`=Available
