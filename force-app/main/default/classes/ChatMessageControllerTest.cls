@IsTest
private class ChatMessageControllerTest {
    @IsTest
    static void testCreateThreadAndMessages() {
        Test.startTest();
        Id threadId = ChatMessageController.createThread('テストスレッド');
        System.assertNotEquals(null, threadId, 'thread created');

        Id msgId = ChatMessageController.postMessage(threadId, 'こんにちは');
        System.assertNotEquals(null, msgId, 'message created');
        Test.stopTest();

        // verify wire method returns message
        List<ChatMessage__c> msgs = ChatMessageController.getMessages(threadId, 10);
        System.assertEquals(1, msgs.size(), 'one message returned');
    }

    @IsTest
    static void testCreateThreadValidation() {
        Boolean thrown = false;
        try {
            ChatMessageController.createThread('');
        } catch (Exception e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected validation exception');
    }
}
