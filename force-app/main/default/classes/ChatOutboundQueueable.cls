public with sharing class ChatOutboundQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> messageIds;
    private static final Integer BATCH_SIZE = 90; // stay under 100 callouts/tx
    // ログ出力の最大文字数（長すぎるレスポンスでデバッグログが溢れないように）
    private static final Integer MAX_LOG_CHARS = 2000;

    public ChatOutboundQueueable(List<Id> messageIds) {
        this.messageIds = messageIds == null ? new List<Id>() : new List<Id>(messageIds);
    }

    public void execute(QueueableContext qc) {
        if (messageIds.isEmpty()) return;
        Integer start = 0;
        while (start < messageIds.size()) {
            Integer endIndex = Math.min(start + BATCH_SIZE, messageIds.size());
            List<Id> chunk = new List<Id>();
            for (Integer i = start; i < endIndex; i++) {
                chunk.add(messageIds[i]);
            }
            processChunk(chunk);
            start = endIndex;
        }
    }

    private static void processChunk(List<Id> ids) {
        if (ids.isEmpty()) return;
        // Query needed data
        List<ChatMessage__c> msgs = [
            SELECT Id, Body__c, PostedBy__c, PostedBy__r.Name, Thread__c,
                   SyncStatus__c,
                   Thread__r.Name, Thread__r.Description__c,
                   Thread__r.RelatedRecordId__c, Thread__r.RelatedObjectType__c
            FROM ChatMessage__c WHERE Id IN :ids
        ];

        List<ChatMessage__c> updates = new List<ChatMessage__c>();
        Http http = new Http();
        for (ChatMessage__c m : msgs) {
            try {
                // ===== 外部連携：Request Body組み立て =====
                // 注意（後で変更しやすいように）：
                //  - 本実装は一時的な外部API仕様に合わせています。
                //  - エンドポイントURLは Named Credential『External_Chat』で管理しています。
                //    現在の想定URL: https://onnxytxwhfarcnlcstut.supabase.co/functions/v1/postman-chat-api
                //  - マッピング仕様（例）:
                //      salesforceRecordId = Thread.RelatedRecordId__c
                //      message            = ChatMessage.Body__c
                //      threadTitle        = Thread.Name
                //      senderName         = ChatMessage.PostedBy__r.Name
                //      salesforceObjectType = Thread.RelatedObjectType__c
                //      messageType        = 'text' 固定
                Map<String, Object> body = new Map<String, Object>{
                    // 重要: 仕様に従い Thread の Salesforce Id を送る
                    //      （以前は RelatedRecordId__c を送っていたが今回の仮APIでは Thread.Id を要求）
                    'salesforceRecordId'   => m.Thread__c,
                    'salesforceObjectType' => m.Thread__r.RelatedObjectType__c,
                    'threadTitle'          => m.Thread__r.Name,
                    'senderName'           => m.PostedBy__r != null ? m.PostedBy__r.Name : null,
                    'message'              => m.Body__c,
                    'messageType'          => 'text'
                };

                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:External_Chat');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setBody(JSON.serialize(body));

                // --- 送信前ログ（デバッグレベル INFO） ---
                logInfo('OutboundRequest',
                       'msgId=' + m.Id + ', threadId=' + m.Thread__c +
                       ', endpoint=External_Chat, body=' + clip(JSON.serialize(body)));

                HttpResponse res = http.send(req);

                // ===== 外部連携：Response処理 =====
                // 成功(2xx)の場合でも、Bodyの内容で結果を判断し、
                //  - data.threadId      → ChatThread.ExternalThreadId__c
                //  - data.messageId     → ChatMessage.ExternalMessageId__c
                //  - error              → ChatMessage.ErrorMessage__c（失敗扱い）
                // を更新します。successやmessageは使用しません。
                ChatMessage__c upd = new ChatMessage__c(Id = m.Id);
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    String resBody = res.getBody();
                    // --- 応答ログ ---
                    logInfo('OutboundResponse',
                           'msgId=' + m.Id + ', status=' + res.getStatusCode() +
                           ', body=' + clip(resBody));
                    String errorMsg;
                    String externalThreadId;
                    String externalMessageId;
                    try {
                        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resBody);
                        if (parsed != null) {
                            // 失敗時: { "error": "..." }
                            if (parsed.containsKey('error')) {
                                errorMsg = (String) parsed.get('error');
                            }
                            // 成功時: { data: { threadId: '...', messageId: '...' }, ... }
                            if (parsed.containsKey('data')) {
                                Map<String, Object> data = (Map<String, Object>) parsed.get('data');
                                if (data != null) {
                                    if (data.containsKey('threadId')) externalThreadId = (String) data.get('threadId');
                                    if (data.containsKey('messageId')) externalMessageId = (String) data.get('messageId');
                                }
                            }
                        }
                    } catch (Exception ignore) {
                        // 予期しない形式はそのまま成功として扱い、詳細はErrorに入れない
                    }

                    if (errorMsg != null) {
                        upd.SyncStatus__c = 'Failed';
                        upd.ErrorMessage__c = 'API error field: ' + errorMsg;
                        logWarn('OutboundParsedError', 'msgId=' + m.Id + ', error=' + errorMsg);
                    } else {
                        upd.SyncStatus__c = 'Synced';
                        upd.ErrorMessage__c = null;
                        if (externalMessageId != null) upd.ExternalMessageId__c = externalMessageId;
                        if (externalThreadId != null) {
                            // Thread側の外部IDは別更新
                            try {
                                update new ChatThread__c(Id = m.Thread__c, ExternalThreadId__c = externalThreadId);
                                logInfo('ThreadExternalIdUpdated', 'threadId=' + m.Thread__c + ', externalThreadId=' + externalThreadId);
                            } catch (Exception ignore) {}
                        }
                    }
                } else {
                    upd.SyncStatus__c = 'Failed';
                    upd.ErrorMessage__c = res.getStatus() + ' ' + res.getBody();
                    logWarn('OutboundHttpError',
                           'msgId=' + m.Id + ', status=' + res.getStatusCode() +
                           ', statusLine=' + res.getStatus() +
                           ', body=' + clip(res.getBody()));
                }
                updates.add(upd);
            } catch (Exception e) {
                ChatMessage__c upd = new ChatMessage__c(
                    Id = m.Id,
                    SyncStatus__c = 'Failed',
                    ErrorMessage__c = 'Exception: ' + e.getMessage()
                );
                logError('OutboundException', 'msgId=' + m.Id + ', error=' + e.getMessage());
                updates.add(upd);
            }
        }
        if (!updates.isEmpty()) update updates;
    }

    // ===== ログ用ヘルパ =====
    // 将来、永続化やカスタムオブジェクトに切り替える場合は以下のメソッドを書き換えるだけで対応可能
    private static void logInfo(String tag, String msg) {
        System.debug(LoggingLevel.INFO, '[ChatOutbound][' + tag + '] ' + msg);
    }
    private static void logWarn(String tag, String msg) {
        System.debug(LoggingLevel.WARN, '[ChatOutbound][' + tag + '] ' + msg);
    }
    private static void logError(String tag, String msg) {
        System.debug(LoggingLevel.ERROR, '[ChatOutbound][' + tag + '] ' + msg);
    }
    private static String clip(String s) {
        if (s == null) return null;
        return s.length() > MAX_LOG_CHARS ? s.substring(0, MAX_LOG_CHARS) + '…(truncated)' : s;
    }
}
