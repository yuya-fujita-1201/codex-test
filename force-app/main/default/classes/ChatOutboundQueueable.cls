public with sharing class ChatOutboundQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> messageIds;
    private static final Integer BATCH_SIZE = 90; // stay under 100 callouts/tx

    public ChatOutboundQueueable(List<Id> messageIds) {
        this.messageIds = messageIds == null ? new List<Id>() : new List<Id>(messageIds);
    }

    public void execute(QueueableContext qc) {
        if (messageIds.isEmpty()) return;
        Integer start = 0;
        while (start < messageIds.size()) {
            Integer end = Math.min(start + BATCH_SIZE, messageIds.size());
            processChunk(messageIds.subList(start, end));
            start = end;
        }
    }

    private static void processChunk(List<Id> ids) {
        if (ids.isEmpty()) return;
        // Query needed data
        List<ChatMessage__c> msgs = [
            SELECT Id, Body__c, PostedBy__c, PostedBy__r.Name, Thread__c,
                   SyncStatus__c,
                   Thread__r.Name, Thread__r.Description__c,
                   Thread__r.RelatedRecordId__c, Thread__r.RelatedObjectType__c
            FROM ChatMessage__c WHERE Id IN :ids
        ];

        List<ChatMessage__c> updates = new List<ChatMessage__c>();
        Http http = new Http();
        for (ChatMessage__c m : msgs) {
            try {
                Map<String, Object> body = new Map<String, Object>{
                    'salesforceRecordId'   => m.Thread__r.RelatedRecordId__c,
                    'salesforceObjectType' => m.Thread__r.RelatedObjectType__c,
                    'threadTitle'          => m.Thread__r.Name,
                    'threadDescription'    => m.Thread__r.Description__c,
                    'senderName'           => m.PostedBy__r != null ? m.PostedBy__r.Name : null,
                    'senderId'             => m.PostedBy__c,
                    'message'              => m.Body__c,
                    'messageType'          => 'text'
                };

                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:External_Chat');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setBody(JSON.serialize(body));

                HttpResponse res = http.send(req);
                ChatMessage__c upd = new ChatMessage__c(Id = m.Id);
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    upd.SyncStatus__c = 'Synced';
                    upd.ErrorMessage__c = null;
                } else {
                    upd.SyncStatus__c = 'Failed';
                    upd.ErrorMessage__c = res.getStatus() + ' ' + res.getBody();
                }
                updates.add(upd);
            } catch (Exception e) {
                ChatMessage__c upd = new ChatMessage__c(Id = m.Id, SyncStatus__c = 'Failed', ErrorMessage__c = e.getMessage());
                updates.add(upd);
            }
        }
        if (!updates.isEmpty()) update updates;
    }
}

