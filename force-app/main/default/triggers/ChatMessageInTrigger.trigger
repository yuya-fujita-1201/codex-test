trigger ChatMessageInTrigger on ChatMessageIn__e (after insert) {
    // Cache external threadId -> SF thread Id
    Set<String> extThreadIds = new Set<String>();
    for (ChatMessageIn__e e : Trigger.new) if (e.ExternalThreadId__c != null) extThreadIds.add(e.ExternalThreadId__c);
    Map<String, Id> threadByExt = new Map<String, Id>();
    if (!extThreadIds.isEmpty()) {
        for (ChatThread__c t : [SELECT Id, ExternalThreadId__c FROM ChatThread__c WHERE ExternalThreadId__c IN :extThreadIds]) {
            threadByExt.put(t.ExternalThreadId__c, t.Id);
        }
    }

    List<ChatMessage__c> upserts = new List<ChatMessage__c>();
    for (ChatMessageIn__e e : Trigger.new) {
        Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(e.Payload__c);
        String body = (String)p.get('body');
        Id threadId = e.ThreadId__c != null ? (Id)e.ThreadId__c : threadByExt.get(e.ExternalThreadId__c);
        ChatMessage__c m = new ChatMessage__c();
        m.ExternalMessageId__c = e.ExternalMessageId__c;
        m.Thread__c = threadId;
        m.Body__c = body;
        m.SyncStatus__c = 'Synced';
        upserts.add(m);
    }
    if (!upserts.isEmpty()) upsert upserts ChatMessage__c.ExternalMessageId__c;
}
