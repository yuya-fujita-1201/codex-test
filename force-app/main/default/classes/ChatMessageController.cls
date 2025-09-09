public with sharing class ChatMessageController {
    @AuraEnabled(cacheable=true)
    public static List<ChatThread__c> getRecentThreads(Integer limitSize) {
        Integer lim = (limitSize == null || limitSize <= 0) ? 20 : limitSize;
        return [
            SELECT Id, Name, Description__c, ExternalThreadId__c, Status__c, CreatedDate
            FROM ChatThread__c
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ];
    }

    @AuraEnabled
    public static Id createThread(String title) {
        if (String.isBlank(title)) throw new AuraHandledException('タイトルは必須です');
        if (title.length() > 80) throw new AuraHandledException('タイトルは80文字以内で入力してください');
        ChatThread__c t = new ChatThread__c(Name = title, Status__c = 'Active');
        insert t;
        return t.Id;
    }

    @AuraEnabled(cacheable=true)
    public static List<ChatMessage__c> getMessages(Id threadId, Integer limitSize) {
        if (threadId == null) return new List<ChatMessage__c>();
        Integer lim = (limitSize == null || limitSize <= 0) ? 50 : limitSize;
        return [
            SELECT Id, Body__c, PostedAt__c, PostedBy__c, PostedBy__r.Name, SyncStatus__c, ErrorMessage__c, ExternalMessageId__c
            FROM ChatMessage__c
            WHERE Thread__c = :threadId
            ORDER BY CreatedDate ASC
            LIMIT :lim
        ];
    }

    @AuraEnabled
    public static Id postMessage(Id threadId, String body) {
        if (threadId == null) throw new AuraHandledException('スレッドが選択されていません');
        if (String.isBlank(body)) throw new AuraHandledException('メッセージ本文は必須です');
        if (body.length() > 1000) throw new AuraHandledException('本文は1000文字以内で入力してください');
        ChatMessage__c m = new ChatMessage__c(
            Thread__c = threadId,
            Body__c = body,
            PostedAt__c = Datetime.now(),
            PostedBy__c = UserInfo.getUserId(),
            SyncStatus__c = 'Pending'
        );
        insert m;
        return m.Id;
    }
}
