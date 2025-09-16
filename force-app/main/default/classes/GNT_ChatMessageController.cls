public with sharing class GNT_ChatMessageController {
    @AuraEnabled(cacheable=true)
    public static List<GNT_ChatThread__c> getRecentThreads(Integer limitSize) {
        Integer lim = (limitSize == null || limitSize <= 0) ? 20 : limitSize;
        return [
            SELECT Id, Name, GNT_Description__c, GNT_ExternalThreadId__c, GNT_Status__c, CreatedDate
            FROM GNT_ChatThread__c
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ];
    }

    // For record-specific view: filter by related record
    @AuraEnabled(cacheable=true)
    public static List<GNT_ChatThread__c> getRecentThreadsForRecord(Id recordId, Integer limitSize) {
        if (recordId == null) return getRecentThreads(limitSize);
        Integer lim = (limitSize == null || limitSize <= 0) ? 20 : limitSize;
        return [
            SELECT Id, Name, GNT_Description__c, GNT_ExternalThreadId__c, GNT_Status__c, CreatedDate, GNT_RelatedRecordId__c, GNT_RelatedObjectType__c
            FROM GNT_ChatThread__c
            WHERE GNT_RelatedRecordId__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ];
    }

    @AuraEnabled
    public static Id createThread(String title) {
        if (String.isBlank(title)) throw new AuraHandledException('タイトルは必須です');
        if (title.length() > 80) throw new AuraHandledException('タイトルは80文字以内で入力してください');
        GNT_ChatThread__c t = new GNT_ChatThread__c(Name = title, GNT_Status__c = 'Active');
        insert t;
        return t.Id;
    }

    // Create a thread associated to a record (record page usage)
    @AuraEnabled
    public static Id createThreadForRecord(String title, Id recordId, String objectApiName) {
        if (String.isBlank(title)) throw new AuraHandledException('タイトルは必須です');
        if (title.length() > 80) throw new AuraHandledException('タイトルは80文字以内で入力してください');
        GNT_ChatThread__c t = new GNT_ChatThread__c(
            Name = title,
            GNT_Status__c = 'Active',
            GNT_RelatedRecordId__c = recordId,
            GNT_RelatedObjectType__c = objectApiName
        );
        insert t;
        return t.Id;
    }

    // Imperative calls from LWC require fresh data to reflect just-posted records.
    // Do not mark cacheable to avoid client-side staleness.
    @AuraEnabled
    public static List<GNT_ChatMessage__c> getMessages(Id threadId, Integer limitSize) {
        if (threadId == null) return new List<GNT_ChatMessage__c>();
        Integer lim = (limitSize == null || limitSize <= 0) ? 50 : limitSize;
        return [
            SELECT Id, GNT_Body__c, GNT_PostedAt__c, GNT_PostedBy__c, CreatedById, CreatedBy.Name, GNT_SyncStatus__c, GNT_ErrorMessage__c, GNT_ExternalMessageId__c
            FROM GNT_ChatMessage__c
            WHERE GNT_Thread__c = :threadId
            ORDER BY CreatedDate ASC
            LIMIT :lim
        ];
    }

    // Pagination for latest-first loading then return ascending for UI
    @AuraEnabled
    public static List<GNT_ChatMessage__c> getMessagesPage(Id threadId, Integer pageSize, Datetime beforeCreatedDate) {
        if (threadId == null) return new List<GNT_ChatMessage__c>();
        Integer lim = (pageSize == null || pageSize <= 0) ? 20 : pageSize;
        if (beforeCreatedDate == null) {
            List<GNT_ChatMessage__c> r = [
                SELECT Id, GNT_Body__c, GNT_PostedAt__c, GNT_PostedBy__c, CreatedById, CreatedBy.Name, GNT_SyncStatus__c, GNT_ErrorMessage__c, GNT_ExternalMessageId__c, CreatedDate
                FROM GNT_ChatMessage__c
                WHERE GNT_Thread__c = :threadId
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
            return reverseList(r);
        } else {
            List<GNT_ChatMessage__c> r = [
                SELECT Id, GNT_Body__c, GNT_PostedAt__c, GNT_PostedBy__c, CreatedById, CreatedBy.Name, GNT_SyncStatus__c, GNT_ErrorMessage__c, GNT_ExternalMessageId__c, CreatedDate
                FROM GNT_ChatMessage__c
                WHERE GNT_Thread__c = :threadId AND CreatedDate < :beforeCreatedDate
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
            return reverseList(r);
        }
    }

    private static List<GNT_ChatMessage__c> reverseList(List<GNT_ChatMessage__c> input) {
        List<GNT_ChatMessage__c> outp = new List<GNT_ChatMessage__c>();
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
        GNT_ChatThread__c th = [SELECT Id, GNT_Status__c FROM GNT_ChatThread__c WHERE Id = :threadId LIMIT 1];
        if (th == null) throw new AuraHandledException('スレッドが見つかりません');
        if (th.GNT_Status__c == 'Closed') throw new AuraHandledException('このスレッドはクローズされています。返信できません');

        // Server-side validation: block when the thread has any non-Synced message
        Integer unsentCount = [SELECT COUNT() FROM GNT_ChatMessage__c WHERE GNT_Thread__c = :threadId AND GNT_SyncStatus__c != 'Synced'];
        if (unsentCount > 0) {
            throw new AuraHandledException('未送信または失敗したメッセージがあります。送信または削除してください。');
        }

        // 外部送信は行わず、メッセージのみ保存（Pending状態）
        GNT_ChatMessage__c m = new GNT_ChatMessage__c(
            GNT_Thread__c = threadId,
            GNT_Body__c = body,
            GNT_PostedAt__c = Datetime.now(),
            GNT_PostedBy__c = UserInfo.getName(),
            GNT_PostedByUser__c = UserInfo.getUserId(),
            GNT_SyncStatus__c = 'Pending',
            GNT_ExternalMessageId__c = null,
            GNT_ErrorMessage__c = null
        );
        insert m;

        return m.Id;
    }

    // 明示送信用：保存済みメッセージを外部に送信し、結果を返す
    @AuraEnabled
    public static GNT_ChatMessage__c sendMessage(Id messageId) {
        if (messageId == null) throw new AuraHandledException('メッセージが選択されていません');
        // 実送信（結果はレコードに反映される）
        GNT_ChatOutboundService.processMessage(messageId);
        // 反映後の状態を返却
        return [
            SELECT Id, GNT_Body__c, GNT_PostedAt__c, GNT_PostedBy__c,
                   GNT_SyncStatus__c, GNT_ErrorMessage__c, GNT_ExternalMessageId__c, CreatedDate, GNT_Thread__c,
                   CreatedById, CreatedBy.Name
            FROM GNT_ChatMessage__c WHERE Id = :messageId LIMIT 1
        ];
    }

    // 削除機能：任意メッセージを削除
    @AuraEnabled
    public static void deleteMessage(Id messageId) {
        if (messageId == null) return;
        delete [SELECT Id FROM GNT_ChatMessage__c WHERE Id = :messageId LIMIT 1];
    }
}
