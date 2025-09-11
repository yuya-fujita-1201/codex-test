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

    // For record-specific view: filter by related record
    @AuraEnabled(cacheable=true)
    public static List<ChatThread__c> getRecentThreadsForRecord(Id recordId, Integer limitSize) {
        if (recordId == null) return getRecentThreads(limitSize);
        Integer lim = (limitSize == null || limitSize <= 0) ? 20 : limitSize;
        return [
            SELECT Id, Name, Description__c, ExternalThreadId__c, Status__c, CreatedDate, RelatedRecordId__c, RelatedObjectType__c
            FROM ChatThread__c
            WHERE RelatedRecordId__c = :recordId
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

    // Create a thread associated to a record (record page usage)
    @AuraEnabled
    public static Id createThreadForRecord(String title, Id recordId, String objectApiName) {
        if (String.isBlank(title)) throw new AuraHandledException('タイトルは必須です');
        if (title.length() > 80) throw new AuraHandledException('タイトルは80文字以内で入力してください');
        ChatThread__c t = new ChatThread__c(
            Name = title,
            Status__c = 'Active',
            RelatedRecordId__c = recordId,
            RelatedObjectType__c = objectApiName
        );
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

    // Pagination for latest-first loading then return ascending for UI
    @AuraEnabled(cacheable=true)
    public static List<ChatMessage__c> getMessagesPage(Id threadId, Integer pageSize, Datetime beforeCreatedDate) {
        if (threadId == null) return new List<ChatMessage__c>();
        Integer lim = (pageSize == null || pageSize <= 0) ? 20 : pageSize;
        if (beforeCreatedDate == null) {
            List<ChatMessage__c> r = [
                SELECT Id, Body__c, PostedAt__c, PostedBy__c, PostedBy__r.Name, SyncStatus__c, ErrorMessage__c, ExternalMessageId__c, CreatedDate
                FROM ChatMessage__c
                WHERE Thread__c = :threadId
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
            return reverseList(r);
        } else {
            List<ChatMessage__c> r = [
                SELECT Id, Body__c, PostedAt__c, PostedBy__c, PostedBy__r.Name, SyncStatus__c, ErrorMessage__c, ExternalMessageId__c, CreatedDate
                FROM ChatMessage__c
                WHERE Thread__c = :threadId AND CreatedDate < :beforeCreatedDate
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
            return reverseList(r);
        }
    }

    private static List<ChatMessage__c> reverseList(List<ChatMessage__c> input) {
        List<ChatMessage__c> outp = new List<ChatMessage__c>();
        for (Integer i = input.size() - 1; i >= 0; i--) {
            outp.add(input[i]);
        }
        return outp;
    }

    @AuraEnabled
    public static Id postMessage(Id threadId, String body) {
        if (threadId == null) throw new AuraHandledException('スレッドが選択されていません');
        if (String.isBlank(body)) throw new AuraHandledException('メッセージ本文は必須です');
        if (body.length() > 1000) throw new AuraHandledException('本文は1000文字以内で入力してください');
        // Server-side validation: block posting to Closed threads
        ChatThread__c th = [SELECT Id, Status__c FROM ChatThread__c WHERE Id = :threadId LIMIT 1];
        if (th == null) throw new AuraHandledException('スレッドが見つかりません');
        if (th.Status__c == 'Closed') throw new AuraHandledException('このスレッドはクローズされています。返信できません');
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
