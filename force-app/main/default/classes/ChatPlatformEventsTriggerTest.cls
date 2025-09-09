@IsTest
private class ChatPlatformEventsTriggerTest {
    @IsTest
    static void testInAndAckTriggers() {
        // prepare thread
        ChatThread__c t = new ChatThread__c(Name = 'T', Status__c = 'Active', ExternalThreadId__c = 'ext-1');
        insert t;

        // Publish inbound event -> should create or upsert message with Synced
        EventBus.publish(new ChatMessageIn__e(
            ExternalThreadId__c = 'ext-1',
            ExternalMessageId__c = 'ext-m-1',
            Payload__c = '{"body":"from external"}'
        ));
        Test.startTest();
        Test.stopTest();

        ChatMessage__c created = [SELECT Id, ExternalMessageId__c, SyncStatus__c FROM ChatMessage__c WHERE ExternalMessageId__c = 'ext-m-1' LIMIT 1];
        System.assertEquals('Synced', created.SyncStatus__c);
    }
}
