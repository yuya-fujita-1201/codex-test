trigger ChatSyncAckTrigger on ChatSyncAck__e (after insert) {
    Map<Id, ChatMessage__c> updates = new Map<Id, ChatMessage__c>();
    for (ChatSyncAck__e e : Trigger.new) {
        if (e.MessageId__c == null) continue;
        Id mid;
        try {
            mid = (Id)e.MessageId__c;
        } catch (Exception ex) {
            continue;
        }
        ChatMessage__c m = new ChatMessage__c(Id = mid);
        m.ExternalMessageId__c = e.ExternalMessageId__c;
        if (e.Success__c == true) {
            m.SyncStatus__c = 'Synced';
            m.ErrorMessage__c = null;
        } else {
            m.SyncStatus__c = 'Failed';
            m.ErrorMessage__c = e.ErrorMessage__c;
        }
        updates.put(m.Id, m);
    }
    if (!updates.isEmpty()) update updates.values();
}

