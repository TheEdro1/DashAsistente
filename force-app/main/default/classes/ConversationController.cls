public with sharing class ConversationController {

    @AuraEnabled(cacheable=true)
    public static List<Conversation__c> getConversations() {
        return [
            SELECT
                Id,
                Name,
                Lead__c,
                Lead__r.Name,
                Channel__c,
                Status__c,
                Needs_Human_Attention__c,
                Assigned_Advisor__c,
                Assigned_Advisor__r.Name,
                Last_Message_At__c,
                Last_Message_Preview__c
            FROM Conversation__c
            ORDER BY Last_Message_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Message__c> getMessages(Id conversationId) {
        if (conversationId == null) {
            return new List<Message__c>();
        }

        return [
            SELECT
                Id,
                Name,
                Conversation__c,
                External_Message_ID__c,
                Direction__c,
                Sender_Type__c,
                Body__c,
                Sent_At__c,
                Status__c,
                Channel__c,
                Sender_Advisor__c,
                Sender_Advisor__r.Name,
                CreatedDate
            FROM Message__c
            WHERE Conversation__c = :conversationId
            ORDER BY CreatedDate ASC
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static void takeConversation(Id conversationId) {
        if (conversationId == null) {
            throw new AuraHandledException('conversationId is required');
        }

        Conversation__c conversation = [
            SELECT Id, Lead__c
            FROM Conversation__c
            WHERE Id = :conversationId
            LIMIT 1
            FOR UPDATE
        ];

        conversation.Status__c = 'Human';
        conversation.Needs_Human_Attention__c = false;
        conversation.Assigned_Advisor__c = UserInfo.getUserId();

        update conversation;

        if (conversation.Lead__c != null) {
            Lead leadToUpdate = new Lead(
                Id = conversation.Lead__c,
                Estado__c = 'advisor',
                Necesita_Atencion__c = false,
                En_Conversacion__c = true,
                Actividad_Actual__c = 'Conversación tomada por el asesor',
                Ultima_Actividad__c = System.now(),
                Razon_Alerta__c = null
            );

            update leadToUpdate;
        }
    }
}