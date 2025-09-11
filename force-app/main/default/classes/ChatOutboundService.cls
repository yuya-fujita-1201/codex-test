public with sharing class ChatOutboundService implements Database.AllowsCallouts {
    // 単一メッセージを外部APIへ送信し、結果に応じて各種フィールドを更新する共通サービス
    // - 将来、外部仕様変更時はこのクラスのRequest/Responseマッピングのみ修正すればよい
    public static void processMessage(Id messageId) {
        if (messageId == null) return;

        ChatMessage__c m = [
            SELECT Id, Body__c, PostedBy__c, PostedBy__r.Name, Thread__c,
                   SyncStatus__c,
                   Thread__r.Name, Thread__r.Description__c,
                   Thread__r.RelatedRecordId__c, Thread__r.RelatedObjectType__c
            FROM ChatMessage__c WHERE Id = :messageId LIMIT 1
        ];

        // Request Body 組立（仕様は仮のため、後で変更しやすいよう日本語コメントで明示）
        // - salesforceRecordId: Thread の Salesforce Id（m.Thread__c）
        // - message           : ChatMessage.Body__c
        // - threadTitle       : Thread.Name
        // - senderName        : ChatMessage.PostedBy__r.Name
        // - salesforceObjectType: Thread.RelatedObjectType__c
        // - messageType       : 'text' 固定
        Map<String, Object> body = new Map<String, Object>{
            'salesforceRecordId'   => m.Thread__c,
            'salesforceObjectType' => m.Thread__r.RelatedObjectType__c,
            'threadTitle'          => m.Thread__r.Name,
            'senderName'           => (m.PostedBy__r != null ? m.PostedBy__r.Name : null),
            'message'              => m.Body__c,
            'messageType'          => 'text'
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:External_Chat');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            ChatMessage__c upd = new ChatMessage__c(Id = m.Id);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                String resBody = res.getBody();
                String errorMsg;
                String externalThreadId;
                String externalMessageId;
                try {
                    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resBody);
                    if (parsed != null) {
                        if (parsed.containsKey('error')) {
                            errorMsg = (String) parsed.get('error');
                        }
                        if (parsed.containsKey('data')) {
                            Map<String, Object> data = (Map<String, Object>) parsed.get('data');
                            if (data != null) {
                                if (data.containsKey('threadId')) externalThreadId = (String) data.get('threadId');
                                if (data.containsKey('messageId')) externalMessageId = (String) data.get('messageId');
                            }
                        }
                    }
                } catch (Exception ignore) {}

                if (errorMsg != null) {
                    upd.SyncStatus__c = 'Failed';
                    upd.ErrorMessage__c = 'API error field: ' + errorMsg;
                } else {
                    upd.SyncStatus__c = 'Synced';
                    upd.ErrorMessage__c = null;
                    if (externalMessageId != null) upd.ExternalMessageId__c = externalMessageId;
                    if (externalThreadId != null) {
                        try { update new ChatThread__c(Id = m.Thread__c, ExternalThreadId__c = externalThreadId); } catch (Exception ignore) {}
                    }
                }
            } else {
                upd.SyncStatus__c = 'Failed';
                upd.ErrorMessage__c = res.getStatus() + ' ' + res.getBody();
            }
            update upd;
        } catch (Exception e) {
            update new ChatMessage__c(Id = m.Id, SyncStatus__c = 'Failed', ErrorMessage__c = 'Exception: ' + e.getMessage());
        }
    }
}

