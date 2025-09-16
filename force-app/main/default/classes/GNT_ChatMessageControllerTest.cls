@IsTest
private class GNT_ChatMessageControllerTest {
    @IsTest
    static void testCreateThreadAndMessages() {
        Test.startTest();
        Id threadId = GNT_ChatMessageController.createThread('テストスレッド');
        System.assertNotEquals(null, threadId, 'thread created');

        Id msgId = GNT_ChatMessageController.postMessage(threadId, 'こんにちは');
        System.assertNotEquals(null, msgId, 'message created');
        Test.stopTest();

        // verify wire method returns message
        List<GNT_ChatMessage__c> msgs = GNT_ChatMessageController.getMessages(threadId, 10);
        System.assertEquals(1, msgs.size(), 'one message returned');
    }

    @IsTest
    static void testCreateThreadValidation() {
        Boolean thrown = false;
        try {
            GNT_ChatMessageController.createThread('');
        } catch (Exception e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected validation exception');
    }
}
