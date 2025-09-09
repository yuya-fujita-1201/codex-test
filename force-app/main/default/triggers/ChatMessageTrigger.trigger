trigger ChatMessageTrigger on ChatMessage__c (after insert, after update) {
    if (!ChatMessageTrigger_RecursionGuard.runOnce()) return;
    List<ChatMessage__c> toUpdate = new List<ChatMessage__c>();
    List<ChatMessage__c> toPublish = new List<ChatMessage__c>();
    for (ChatMessage__c m : Trigger.new) {
        // Skip records that originated from external system (have ExternalMessageId__c)
        if (m.ExternalMessageId__c != null) continue;
        ChatMessage__c oldM = Trigger.isUpdate ? Trigger.oldMap.get(m.Id) : null;
        Boolean isChanged = Trigger.isInsert || (oldM.Body__c != m.Body__c);
        if (isChanged) {
            ChatMessage__c upd = new ChatMessage__c(Id = m.Id);
            upd.SyncStatus__c = 'Pending';
            // set PostedAt if not set
            if (m.PostedAt__c == null) upd.PostedAt__c = Datetime.now();
            toUpdate.add(upd);
            toPublish.add(m);
        }
    }
    if (!toUpdate.isEmpty()) update toUpdate;
    if (!toPublish.isEmpty()) ChatEventBus.publishMessageOut(toPublish);
}
