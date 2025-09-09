public with sharing class ChatEventBus {
    public static void publishMessageOut(List<ChatMessage__c> records) {
        if (records == null || records.isEmpty()) return;
        List<ChatMessageOut__e> events = new List<ChatMessageOut__e>();
        Datetime nowDt = Datetime.now();
        for (ChatMessage__c m : records) {
            Map<String, Object> payload = new Map<String, Object>{
                'body' => m.Body__c,
                'postedBy' => m.PostedBy__c,
                'postedAt' => (m.PostedAt__c != null ? m.PostedAt__c : nowDt)
            };
            events.add(new ChatMessageOut__e(
                Operation__c = (m.ExternalMessageId__c == null ? 'Create' : 'Update'),
                MessageId__c = (String)m.Id,
                ThreadId__c = (String)m.Thread__c,
                Version__c = 'v1',
                Payload__c = JSON.serialize(payload)
            ));
        }
        EventBus.publish(events);
    }
}

