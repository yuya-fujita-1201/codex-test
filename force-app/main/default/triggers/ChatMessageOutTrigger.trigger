trigger ChatMessageOutTrigger on ChatMessageOut__e (after insert) {
    List<Id> messageIds = new List<Id>();
    for (ChatMessageOut__e e : Trigger.new) {
        if (e.MessageId__c != null) {
            try {
                messageIds.add((Id)e.MessageId__c);
            } catch (Exception ex) {
                // ignore invalid ids
            }
        }
    }
    if (!messageIds.isEmpty()) {
        System.enqueueJob(new ChatOutboundQueueable(messageIds));
    }
}

