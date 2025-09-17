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

    private static GNT_ChatThread__c createThread(Boolean closed, Boolean withRelated) {
        return new GNT_ChatThread__c(
            Name = closed ? 'Closed Thread' : 'Open Thread',
            GNT_Status__c = closed ? 'Closed' : 'Active',
            GNT_Description__c = '説明',
            GNT_RelatedRecordId__c = withRelated ? '001000000000001' : null,
            GNT_RelatedObjectType__c = withRelated ? 'Account' : null
        );
    }

    private static GNT_ChatMessage__c createMessage(Id threadId, String status, String body) {
        return new GNT_ChatMessage__c(
            GNT_Thread__c = threadId,
            GNT_Body__c = body,
            GNT_PostedAt__c = System.now().addSeconds(-10),
            GNT_PostedBy__c = 'Tester',
            GNT_PostedByUser__c = UserInfo.getUserId(),
            GNT_SyncStatus__c = status,
            GNT_ErrorMessage__c = null,
            GNT_ExternalMessageId__c = null
        );
    }

    @IsTest
    static void testThreadQueriesAndCreation() {
        List<GNT_ChatThread__c> threads = new List<GNT_ChatThread__c>{
            createThread(false, false),
            createThread(false, true)
        };
        insert threads;

        Test.startTest();
        List<GNT_ChatThread__c> recent = GNT_ChatMessageController.getRecentThreads(5);
        List<GNT_ChatThread__c> recentForRecord = GNT_ChatMessageController.getRecentThreadsForRecord('001000000000001', 5);
        Test.stopTest();

        System.assertEquals(2, recent.size(), 'Should retrieve both threads');
        System.assertEquals(1, recentForRecord.size(), 'Filtered list should have a single thread');

        Test.startTest();
        Id newThreadId = GNT_ChatMessageController.createThread('新しいスレッド');
        Id recordThreadId = GNT_ChatMessageController.createThreadForRecord('関連付き', '001000000000002', 'Account');
        Test.stopTest();

        System.assertNotEquals(null, newThreadId, 'createThread should return Id');
        System.assertNotEquals(null, recordThreadId, 'createThreadForRecord should return Id');

        GNT_ChatThread__c created = [SELECT GNT_Status__c FROM GNT_ChatThread__c WHERE Id = :newThreadId];
        System.assertEquals('Active', created.GNT_Status__c, 'New thread should be Active');
    }

    @IsTest
    static void testPostMessageValidationsAndQueries() {
        GNT_ChatThread__c thread = createThread(false, false);
        insert thread;

        // Validation: blank title handled by createThread
        try {
            GNT_ChatMessageController.createThread('');
            System.assert(false, 'Expected AuraHandledException for blank title');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('タイトルは必須です'));
        }

        // postMessage validation for null thread
        try {
            GNT_ChatMessageController.postMessage(null, '本文');
            System.assert(false, 'Expected AuraHandledException for null thread');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('スレッドが選択されていません'));
        }

        // Body validation
        try {
            GNT_ChatMessageController.postMessage(thread.Id, '');
            System.assert(false, 'Expected AuraHandledException for blank body');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('メッセージ本文は必須です'));
        }

        // Closed thread validation
        GNT_ChatThread__c closed = createThread(true, false);
        insert closed;
        try {
            GNT_ChatMessageController.postMessage(closed.Id, 'NG');
            System.assert(false, 'Expected AuraHandledException for closed thread');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('クローズ'));
        }

        // Happy path posting + queries
        Id messageId = GNT_ChatMessageController.postMessage(thread.Id, 'こんにちは');
        System.assertNotEquals(null, messageId, 'Message should be created');

        List<GNT_ChatMessage__c> firstPage = GNT_ChatMessageController.getMessages(thread.Id, 5);
        System.assertEquals(1, firstPage.size(), 'Initial page size');
        System.assertEquals('こんにちは', firstPage[0].GNT_Body__c, 'Body should match');

        // Create additional messages to exercise pagination
        insert new List<GNT_ChatMessage__c>{
            createMessage(thread.Id, 'Synced', '過去1'),
            createMessage(thread.Id, 'Synced', '過去2')
        };
        Datetime boundary = System.now().addSeconds(1);
        List<GNT_ChatMessage__c> paged = GNT_ChatMessageController.getMessagesPage(thread.Id, 2, boundary);
        System.assertEquals(2, paged.size(), 'Pagination should return two entries');

        // Reverse order branch (with beforeCreatedDate = null)
        List<GNT_ChatMessage__c> latestPage = GNT_ChatMessageController.getMessagesPage(thread.Id, 2, null);
        System.assertEquals(true, latestPage[0].CreatedDate <= latestPage[1].CreatedDate);

        // deleteMessage coverage
        GNT_ChatMessageController.deleteMessage(messageId);
        System.assertEquals(0, [SELECT COUNT() FROM GNT_ChatMessage__c WHERE Id = :messageId]);
    }

    @IsTest
    static void testSendMessageSuccessAndCalloutHelpers() {
        GNT_ChatThread__c thread = createThread(false, true);
        insert thread;
        Id messageId = GNT_ChatMessageController.postMessage(thread.Id, 'Callout Body');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ExternalChatSuccessMock());
        GNT_ChatMessage__c result = GNT_ChatMessageController.sendMessage(messageId);
        Test.stopTest();

        System.assertEquals('Synced', result.GNT_SyncStatus__c, 'Successful send should mark synced');
        System.assertEquals('EXT-MSG', result.GNT_ExternalMessageId__c, 'External message id should be stored');

        // callExternalForThread coverage (uses same mock)
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ExternalChatSuccessMock());
        GNT_ChatOutboundService.Result preview = GNT_ChatOutboundService.callExternalForThread(thread.Id, 'Preview');
        Test.stopTest();

        System.assert(preview.ok, 'Preview call should be ok');
        System.assertEquals('EXT-MSG', preview.externalMessageId);
    }

    @IsTest
    static void testSendMessageFailureBranches() {
        GNT_ChatThread__c thread = createThread(false, false);
        insert thread;
        GNT_ChatMessage__c message = createMessage(thread.Id, 'Pending', 'Failure Path');
        insert message;

        // HTTP error response branch
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ExternalChatErrorMock());
        GNT_ChatOutboundService.processMessage(message.Id);
        Test.stopTest();
        GNT_ChatMessage__c errored = [SELECT GNT_SyncStatus__c, GNT_ErrorMessage__c FROM GNT_ChatMessage__c WHERE Id = :message.Id];
        System.assertEquals('Failed', errored.GNT_SyncStatus__c, 'Error response should set failed');
        System.assert(errored.GNT_ErrorMessage__c.contains('integration outage'));

        // Exception branch
        message = createMessage(thread.Id, 'Pending', 'Exception Path');
        insert message;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ExternalChatExceptionMock());
        GNT_ChatOutboundService.processMessage(message.Id);
        Test.stopTest();
        errored = [SELECT GNT_SyncStatus__c, GNT_ErrorMessage__c FROM GNT_ChatMessage__c WHERE Id = :message.Id];
        System.assertEquals('Failed', errored.GNT_SyncStatus__c, 'Exception should mark failed');
        System.assert(errored.GNT_ErrorMessage__c.contains('Exception: Simulated transport error'));
    }
}
