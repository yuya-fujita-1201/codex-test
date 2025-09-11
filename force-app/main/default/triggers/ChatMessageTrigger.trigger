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
            // Controller側で最終ステータスを設定するため、ここではステータスは変更しない
            // PostedAt が欠けている場合のみ補正
            if (m.PostedAt__c == null) {
                ChatMessage__c upd = new ChatMessage__c(Id = m.Id, PostedAt__c = Datetime.now());
                toUpdate.add(upd);
            }
        }
    }
    if (!toUpdate.isEmpty()) update toUpdate;
    // 外部連携はController（同期Callout）に一本化したため、PEは発行しない
    // if (!toPublish.isEmpty() && !ChatMessageTrigger_RecursionGuard.skipOutbound) ChatEventBus.publishMessageOut(toPublish);
}
