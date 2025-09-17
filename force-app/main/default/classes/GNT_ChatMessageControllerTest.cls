@IsTest
private class GNT_ChatMessageControllerTest {
    private class ExternalChatSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"data":{"threadId":"EXT-TH","messageId":"EXT-MSG"}}');
            return res;
        }
    }

    private class ExternalChatErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(502);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"integration outage"}');
            return res;
        }
    }

    private class ExternalChatExceptionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Simulated transport error');
        }
    }

    private static final Id RELATED_ID = Id.valueOf('001000000000001AAA');

    private static GNT_ChatThread__c newThread(Boolean closed, Boolean withRelated) {
        return new GNT_ChatThread__c(
            Name = closed ? 'Closed Thread' : 'Open Thread',
            GNT_Status__c = closed ? 'Closed' : 'Active',
            GNT_RelatedRecordId__c = withRelated ? String.valueOf(RELATED_ID) : null,
            GNT_RelatedObjectType__c = withRelated ? 'Account' : null
        );
    }

    private static GNT_ChatMessage__c newMessage(Id threadId, String status, String body) {
        return new GNT_ChatMessage__c(
            GNT_Thread__c = threadId,
            GNT_Body__c = body,
            GNT_PostedAt__c = System.now().addSeconds(-60),
            GNT_PostedBy__c = 'Tester',
            GNT_SyncStatus__c = status,
            GNT_ErrorMessage__c = null,
            GNT_ExternalMessageId__c = null
        );
    }

    private static void invokeProcessMessage(Id messageId, HttpCalloutMock mock) {
        Test.startTest();
        try {
            Test.setMock(HttpCalloutMock.class, mock);
            GNT_ChatOutboundService.processMessage(messageId);
        } finally {
            Test.stopTest();
        }
    }

    private static GNT_ChatMessage__c invokeSendMessage(Id messageId, HttpCalloutMock mock) {
        Test.startTest();
        try {
            Test.setMock(HttpCalloutMock.class, mock);
            return GNT_ChatMessageController.sendMessage(messageId);
        } finally {
            Test.stopTest();
        }
    }

    @IsTest
    static void testThreadQueriesAndCreation() {
        GNT_ChatMessageController.resetSingleThreadModeCache();
        List<GNT_ChatThread__c> seed = new List<GNT_ChatThread__c>{
            newThread(false, false),
            newThread(false, true)
        };
        insert seed;

        List<GNT_ChatThread__c> recent = GNT_ChatMessageController.getRecentThreads(5);
        List<GNT_ChatThread__c> recentForRecord = GNT_ChatMessageController.getRecentThreadsForRecord(RELATED_ID, 5);

        Set<Id> recentIds = new Set<Id>();
        for (GNT_ChatThread__c t : recent) {
            recentIds.add(t.Id);
        }
        System.assertEquals(true, recentIds.containsAll(new Set<Id>{ seed[0].Id, seed[1].Id }), 'Recent threads should include inserted records');
        if (!recentForRecord.isEmpty()) {
            System.assertEquals(seed[1].Id, recentForRecord[0].Id);
        }
        System.assertEquals(1, [SELECT COUNT() FROM GNT_ChatThread__c WHERE GNT_RelatedRecordId__c = :String.valueOf(RELATED_ID)]);

        Id autoThreadId = GNT_ChatMessageController.createThread('新しいスレッド');
        Id recordThreadId = GNT_ChatMessageController.createThreadForRecord('関連付き', '001000000000002AAA', 'Account');
        System.assertNotEquals(null, autoThreadId);
        System.assertNotEquals(null, recordThreadId);

        GNT_ChatThread__c created = [SELECT GNT_Status__c FROM GNT_ChatThread__c WHERE Id = :autoThreadId];
        System.assertEquals('Active', created.GNT_Status__c);
    }

    @IsTest
    static void testPostMessageValidationsAndQueries() {
        GNT_ChatMessageController.resetSingleThreadModeCache();
        GNT_ChatThread__c thread = newThread(false, false);
        insert thread;

        Boolean threw;

        threw = false;
        try {
            GNT_ChatMessageController.createThread('');
        } catch (AuraHandledException expected) {
            threw = true;
        }
        System.assert(threw, 'Expected exception for blank title');

        threw = false;
        try {
            GNT_ChatMessageController.postMessage(null, '本文');
        } catch (AuraHandledException expected) {
            threw = true;
        }
        System.assert(threw, 'Expected exception for null thread');

        threw = false;
        try {
            GNT_ChatMessageController.postMessage(thread.Id, '');
        } catch (AuraHandledException expected) {
            threw = true;
        }
        System.assert(threw, 'Expected exception for blank body');

        GNT_ChatThread__c closed = newThread(true, false);
        insert closed;
        threw = false;
        try {
            GNT_ChatMessageController.postMessage(closed.Id, 'NG');
        } catch (AuraHandledException expected) {
            threw = true;
        }
        System.assert(threw, 'Expected exception for closed thread');

        // Happy path insert and retrieval
        Id messageId = GNT_ChatMessageController.postMessage(thread.Id, 'こんにちは');
        System.assertNotEquals(null, messageId);

        List<GNT_ChatMessage__c> firstPage = GNT_ChatMessageController.getMessages(thread.Id, 5);
        System.assertEquals(1, firstPage.size());
        System.assertEquals('こんにちは', firstPage[0].GNT_Body__c);

        insert new List<GNT_ChatMessage__c>{
            newMessage(thread.Id, 'Synced', '過去1'),
            newMessage(thread.Id, 'Synced', '過去2')
        };

        List<GNT_ChatMessage__c> paged = GNT_ChatMessageController.getMessagesPage(thread.Id, 2, System.now().addSeconds(1));
        System.assertEquals(2, paged.size());

        List<GNT_ChatMessage__c> latestPage = GNT_ChatMessageController.getMessagesPage(thread.Id, 2, null);
        System.assertEquals(true, !latestPage.isEmpty(), 'Latest page returns data');

        GNT_ChatMessageController.deleteMessage(messageId);
        System.assertEquals(0, [SELECT COUNT() FROM GNT_ChatMessage__c WHERE Id = :messageId]);
    }

    @IsTest
    static void testSendMessageSuccessAndCalloutHelpers() {
        GNT_ChatMessageController.resetSingleThreadModeCache();
        GNT_ChatThread__c thread = newThread(false, true);
        insert thread;
        Id messageId = GNT_ChatMessageController.postMessage(thread.Id, 'Callout Body');

        GNT_ChatMessage__c result = invokeSendMessage(messageId, new ExternalChatSuccessMock());

        System.assertEquals('Synced', result.GNT_SyncStatus__c);
        System.assertEquals('EXT-MSG', result.GNT_ExternalMessageId__c);

        Test.setMock(HttpCalloutMock.class, new ExternalChatSuccessMock());
        GNT_ChatOutboundService.Result preview = GNT_ChatOutboundService.callExternalForThread(thread.Id, 'Preview');
        System.assert(preview.ok);
        System.assertEquals('EXT-MSG', preview.externalMessageId);
    }

    @IsTest
    static void testSendMessageFailureBranches() {
        GNT_ChatMessageController.resetSingleThreadModeCache();
        GNT_ChatThread__c thread = newThread(false, false);
        insert thread;

        // HTTP error branch
        GNT_ChatMessage__c message = newMessage(thread.Id, 'Pending', 'Failure Path');
        insert message;
        Test.setMock(HttpCalloutMock.class, new ExternalChatErrorMock());
        GNT_ChatOutboundService.processMessage(message.Id);
        GNT_ChatMessage__c errored = [SELECT GNT_SyncStatus__c, GNT_ErrorMessage__c FROM GNT_ChatMessage__c WHERE Id = :message.Id];
        System.assertEquals('Failed', errored.GNT_SyncStatus__c);
        System.assertNotEquals(null, errored.GNT_ErrorMessage__c);

        // Exception branch
        message = newMessage(thread.Id, 'Pending', 'Exception Path');
        insert message;
        Test.setMock(HttpCalloutMock.class, new ExternalChatExceptionMock());
        GNT_ChatOutboundService.processMessage(message.Id);
        errored = [SELECT GNT_SyncStatus__c, GNT_ErrorMessage__c FROM GNT_ChatMessage__c WHERE Id = :message.Id];
        System.assertEquals('Failed', errored.GNT_SyncStatus__c);
        System.assertNotEquals(null, errored.GNT_ErrorMessage__c);
    }

    @IsTest
    static void testSingleThreadModeToggle() {
        GNT_ChatMessageController.resetSingleThreadModeCache();
        try {
            GNT_ChatMessageController.setSingleThreadModeForTest(false);
            Id multiRecordId = '001000000000010AAA';
            Id first = GNT_ChatMessageController.createThreadForRecord('First Multi Thread', multiRecordId, 'Account');
            System.assertNotEquals(null, first);
            Id second = GNT_ChatMessageController.createThreadForRecord('Second Multi Thread', multiRecordId, 'Account');
            System.assertNotEquals(null, second, 'Second thread should be allowed when single-thread mode is disabled');

            GNT_ChatMessageController.setSingleThreadModeForTest(true);
            Id restrictedRecordId = '001000000000011AAA';
            Id allowed = GNT_ChatMessageController.createThreadForRecord('First Restricted Thread', restrictedRecordId, 'Account');
            System.assertNotEquals(null, allowed);

            Boolean blocked = false;
            try {
                GNT_ChatMessageController.createThreadForRecord('Blocked Restricted Thread', restrictedRecordId, 'Account');
            } catch (AuraHandledException expected) {
                blocked = true;
            }
            System.assert(blocked, 'Second thread should be blocked when single-thread mode is enabled');
        } finally {
            GNT_ChatMessageController.resetSingleThreadModeCache();
        }
    }
}