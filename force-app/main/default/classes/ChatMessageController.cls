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
        if (String.isBlank(title)) throw new AuraHandledException('Title is required');
        if (title.length() > 80) throw new AuraHandledException('Title must be 80 characters or less');
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
        if (threadId == null) throw new AuraHandledException('ThreadId is required');
        if (String.isBlank(body)) throw new AuraHandledException('Message body is required');
        if (body.length() > 1000) throw new AuraHandledException('Body must be 1000 characters or less');
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
