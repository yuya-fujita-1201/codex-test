@IsTest
private class ChatOutboundQueueableTest {
    private class OkMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    @IsTest
    static void testQueueableUpdatesStatus() {
        // prepare data
        ChatThread__c t = new ChatThread__c(Name = 'T1', Status__c = 'Active');
        insert t;
        ChatMessage__c m = new ChatMessage__c(Thread__c = t.Id, Body__c = 'Hi', PostedBy__c = UserInfo.getUserId());
        insert m;

        Test.setMock(HttpCalloutMock.class, new OkMock());
        Test.startTest();
        System.enqueueJob(new ChatOutboundQueueable(new List<Id>{ m.Id }));
        Test.stopTest();

        m = [SELECT SyncStatus__c, ErrorMessage__c FROM ChatMessage__c WHERE Id = :m.Id];
        System.assertEquals('Synced', m.SyncStatus__c, 'status updated to Synced');
        System.assertEquals(null, m.ErrorMessage__c, 'no error');
    }
}

