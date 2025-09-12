public with sharing class ChatOutboundService implements Database.AllowsCallouts {
    public class Result {
        @AuraEnabled public Boolean ok;
        @AuraEnabled public String externalThreadId;
        @AuraEnabled public String externalMessageId;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public String rawBody;
    }

    // コールアウト先行用：Threadと本文から外部APIを呼び出し、結果だけ返す
    public static Result callExternalForThread(Id threadId, String messageBody) {
        if (threadId == null) throw new AuraHandledException('スレッドが見つかりません');
        Result r = new Result();

        ChatThread__c th = [
            SELECT Id, Name, RelatedObjectType__c, RelatedRecordId__c
            FROM ChatThread__c WHERE Id = :threadId LIMIT 1
        ];
        User u = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // 外部側の最新仕様に合わせて以下のJSONで送信
        // {
        //   salesforceRecordId, salesforceObjectType, threadTitle, threadDescription,
        //   senderName, senderId, message, messageType
        // }
        // 外部側のRLS要件: salesforceRecordId は関連レコード（例: Account/Case等）のIdを送る想定
        // 互換のため、関連が無い場合はThread.Idをフォールバック
        Id relatedId = th.RelatedRecordId__c;
        if (relatedId == null) relatedId = th.Id;
        Map<String, Object> body = new Map<String, Object>{
            'salesforceRecordId'   => relatedId,
            'salesforceObjectType' => th.RelatedObjectType__c,
            'threadTitle'          => th.Name,
            'senderName'           => u != null ? u.Name : null,
            'senderId'             => UserInfo.getUserId(),
            // 追加送信: SF側のThreadを明示（外部が将来採用する場合に備えた補助キー）
            'salesforceThreadId'   => th.Id,
            'message'              => messageBody,
            'messageType'          => 'text'
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:External_Chat');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(req);
        r.statusCode = res.getStatusCode();
        r.rawBody = res.getBody();
        if (r.statusCode >= 200 && r.statusCode < 300) {
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(r.rawBody);
                if (parsed != null) {
                    if (parsed.containsKey('error')) r.errorMessage = (String) parsed.get('error');
                    if (parsed.containsKey('data')) {
                        Map<String, Object> data = (Map<String, Object>) parsed.get('data');
                        if (data != null) {
                            if (data.containsKey('threadId')) r.externalThreadId = (String) data.get('threadId');
                            if (data.containsKey('messageId')) r.externalMessageId = (String) data.get('messageId');
                        }
                    }
                }
            } catch (Exception ignore) {}
        } else {
            r.errorMessage = res.getStatus() + ' ' + r.rawBody;
        }
        r.ok = (r.errorMessage == null);
        return r;
    }
    // 単一メッセージを外部APIへ送信し、結果に応じて各種フィールドを更新する共通サービス
    // - 将来、外部仕様変更時はこのクラスのRequest/Responseマッピングのみ修正すればよい
    public static void processMessage(Id messageId) {
        if (messageId == null) return;

        ChatMessage__c m = [
            SELECT Id, Body__c, PostedBy__c, PostedBy__r.Name, Thread__c,
                   SyncStatus__c,
                   Thread__r.Name,
                   Thread__r.RelatedRecordId__c, Thread__r.RelatedObjectType__c
            FROM ChatMessage__c WHERE Id = :messageId LIMIT 1
        ];

        // Request Body 組立（仕様は仮のため、後で変更しやすいよう日本語コメントで明示）
        // 外部側の最新仕様に合わせた送信ボディ
        // - salesforceRecordId: Thread の Salesforce Id（m.Thread__c）
        // - salesforceObjectType: Thread.RelatedObjectType__c
        // - threadTitle       : Thread.Name
        // - threadDescription : Thread.Description__c
        // - senderName        : ChatMessage.PostedBy__r.Name
        // - senderId          : ChatMessage.PostedBy__c
        // - message           : ChatMessage.Body__c
        // - messageType       : 'text' 固定
        Id relId = m.Thread__r.RelatedRecordId__c;
        if (relId == null) relId = m.Thread__c;
        Map<String, Object> body = new Map<String, Object>{
            'salesforceRecordId'   => relId,
            'salesforceObjectType' => m.Thread__r.RelatedObjectType__c,
            'threadTitle'          => m.Thread__r.Name,
            'senderName'           => (m.PostedBy__r != null ? m.PostedBy__r.Name : null),
            'senderId'             => m.PostedBy__c,
            'salesforceThreadId'   => m.Thread__c,
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
