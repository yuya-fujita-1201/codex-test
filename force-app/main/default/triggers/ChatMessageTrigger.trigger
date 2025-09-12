trigger ChatMessageTrigger on ChatMessage__c (after insert, after update) {
    List<ChatMessage__c> toUpdate = new List<ChatMessage__c>();
    for (ChatMessage__c m : Trigger.new) {
        if (m.PostedAt__c == null) {
            toUpdate.add(new ChatMessage__c(Id = m.Id, PostedAt__c = Datetime.now()));
        }
    }
    if (!toUpdate.isEmpty()) update toUpdate;
}
