## 機能定義（Apex / トリガ）

### Apex クラス
- `GNT_ChatMessageController`
  - `@AuraEnabled cacheable=true List<GNT_ChatThread__c> getRecentThreads(Integer limitSize)`
  - `@AuraEnabled Id createThread(String title)`
  - `@AuraEnabled cacheable=true List<GNT_ChatMessage__c> getMessages(Id threadId, Integer limitSize)`
  - `@AuraEnabled Id postMessage(Id threadId, String body)`
  - バリデーションメッセージは日本語化済み。

- `ChatEventBus`
  - `publishMessageOut(List<GNT_ChatMessage__c>)`: Salesforce 内の変更を `ChatMessageOut__e` として配信。

- `ChatOutboundQueueable`（`Queueable`, `Database.AllowsCallouts`）
  - `execute`: `GNT_ChatMessage__c` をバッチ分割して外部にPOST（Named Credential `External_Chat` 経由）。
  - 成功/失敗に応じて `GNT_SyncStatus__c` と `GNT_ErrorMessage__c` を更新。

### トリガ
- `GNT_ChatMessageTrigger`（after insert, after update）
  - Salesforce 由来のメッセージのみ（`GNT_ExternalMessageId__c = null`）を対象に、
    `GNT_SyncStatus__c` を `Pending` に更新、`ChatMessageOut__e` を発行。

- `ChatMessageOutTrigger`（`ChatMessageOut__e` after insert）
  - `MessageId__c` を収集して `ChatOutboundQueueable` を enqueue。

- `ChatMessageInTrigger`（`ChatMessageIn__e` after insert）
  - 受信ペイロードから `GNT_ChatMessage__c` を upsert（外部ID基準）。`GNT_SyncStatus__c='Synced'`。

- `ChatSyncAckTrigger`（`ChatSyncAck__e` after insert）
  - ACK に応じて `GNT_ChatMessage__c` のステータス/エラーを更新。

### テスト
- `GNT_ChatMessageControllerTest`
- `ChatOutboundQueueableTest`（`HttpCalloutMock` で外部送信をモック）
- `ChatPlatformEventsTriggerTest`（受信イベントの取り込み確認）
