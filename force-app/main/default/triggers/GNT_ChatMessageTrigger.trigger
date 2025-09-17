trigger GNT_ChatMessageTrigger on GNT_ChatMessage__c (after insert, after update) {
    List<GNT_ChatMessage__c> toUpdate = new List<GNT_ChatMessage__c>();
    for (GNT_ChatMessage__c m : Trigger.new) {
        if (m.GNT_PostedAt__c == null) {
            toUpdate.add(new GNT_ChatMessage__c(Id = m.Id, GNT_PostedAt__c = Datetime.now()));
        }
    }
    if (!toUpdate.isEmpty()) update toUpdate;
}