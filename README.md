Custom Chat (Platform Event-based) — SFDX Slice

What’s included
- Custom objects: `ChatThread__c` (Title uses Name 80 chars), `ChatMessage__c` (Body 1000 chars)
- Platform Events: `ChatMessageOut__e`, `ChatSyncAck__e`, `ChatMessageIn__e`
- Apex: Event publisher, 3 triggers, LWC controller
- LWC: `chatWorkspace` (threads + messages), `chatThreadList`, `chatMessagePanel`

Deploy
- Authenticate to your org, then:
  - `sf project deploy start --source-dir force-app`

Place the UI
- In App Builder, drop `chatWorkspace` on an App/Home page.
- Optionally, add `threadRelatedEditor` to the `ChatThread__c` record page to edit Related Record/Object/Description.

Field constraints
- Title (`ChatThread__c.Name`): up to 80 chars (standard)
- Content (`ChatMessage__c.Body__c`): Long Text Area length 1000
- LWC inputs and Apex both validate these limits.

Sync flow (Platform Events + HTTP)
- SF → External (HTTP POST):
  - `ChatMessageTrigger` marks Pending and publishes `ChatMessageOut__e`.
  - `ChatMessageOutTrigger` enqueues `ChatOutboundQueueable` which POSTs to Named Credential `External_Chat`.
  - 成否によって `SyncStatus__c` を `Synced`/`Failed` に更新（✅/⚠️）。
- External ACK → SF (optional): 代替で`ChatSyncAck__e`をPublishしても運用可能。
- External → SF message: `ChatMessageIn__e`をPublish（`Payload__c`に`{"body":"..."}`）→ Upsert。

Outbound HTTP payload
- Endpoint (Named Credential `External_Chat`):
  - `https://onnxytxwhfarcnlcstut.supabase.co/functions/v1/receive-from-salesforce`
- JSON body example:
  {
    "salesforceRecordId": "001XXXXXXXXXX",          // from `ChatThread__c.RelatedRecordId__c`
    "salesforceObjectType": "Account",               // from `ChatThread__c.RelatedObjectType__c`
    "threadTitle": "...",                            // `ChatThread__c.Name`
    "threadDescription": "...",                      // `ChatThread__c.Description__c`
    "senderName": "...",                             // `ChatMessage__c.GNT_PostedBy__c`
    "senderId": "005XXXXXXXXXX",                     // `ChatMessage__c.CreatedById`
    "message": "...",                                 // `ChatMessage__c.Body__c`
    "messageType": "text"
  }

Notes
- Name(80) をスレッドタイトルとして使用します。
- `ChatMessage__c.Thread__c` is Master-Detail for cascade delete and rollups; adjust to Lookup if needed.
- Add a Permission Set granting object/field access and LWC Apex class access before rollout.

Setup
- Named Credential `External_Chat` は上記URLにAnonymousで作成済み（メタデータ同梱）。
- 認証が必要な場合はNamed Credentialを変更してください。
- Permission Set: Assign `Custom Chat User` to end users for object/field and Apex access.
