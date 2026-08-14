@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class AgentAutoRespondAction {
  @InvocableMethod(
    label='Auto-Respond Agentforce'
    description='Invoca al agente de Agentforce para responder al mensaje entrante y envía la respuesta por el canal configurado.'
    category='Messaging'
  )
  public static List<String> autoRespond(List<String> messageIds) {
    List<String> results = new List<String>();
    if (messageIds == null || messageIds.isEmpty()) {
      return results;
    }
    for (String messageId : messageIds) {
      String result = processOne(messageId);
      results.add(result);
    }
    return results;
  }

  private static String processOne(String messageId) {
    if (String.isBlank(messageId)) {
      return 'SKIP: messageId blank';
    }
    try {
      Message__c incoming = [
        SELECT Id, Conversation__c, Body__c
        FROM Message__c
        WHERE Id = :messageId
        LIMIT 1
      ];
      if (incoming.Conversation__c == null) {
        return 'SKIP: no conversation for msg=' + messageId;
      }

      Map<String, Object> convBindings = new Map<String, Object>{ 'cid' => incoming.Conversation__c };
      List<Conversation__c> convs = (List<Conversation__c>) Database.queryWithBinds(
        'SELECT Id, Status__c, Channel__c, External_Participant_ID__c, Last_Inbound_At__c ' +
        'FROM Conversation__c ' +
        'WHERE Id = :cid ' +
        'LIMIT 1',
        convBindings,
        AccessLevel.SYSTEM_MODE
      );
      if (convs.isEmpty()) {
        return 'SKIP: conversation not found';
      }
      Conversation__c conversation = convs[0];
      if (conversation.Status__c != 'Bot') {
        return 'SKIP: status=' + conversation.Status__c;
      }

      String promptBody = String.isBlank(incoming.Body__c)
        ? '[Mensaje sin texto - cliente envió adjunto]'
        : incoming.Body__c;
      AdvisorAssistantController.AssistantResponse agentResponse = AdvisorAssistantController.invokeAgentNonAura(
        promptBody,
        null
      );
      String replyText = agentResponse == null ? null : agentResponse.text;
      if (String.isBlank(replyText)) {
        return 'SKIP: agent returned blank';
      }

      String externalId;
      String providerError;
      String sendStatus = 'Sent';
      if (conversation.Channel__c == 'WhatsApp') {
        Long lastInboundMs = conversation.Last_Inbound_At__c == null
          ? 0L
          : conversation.Last_Inbound_At__c.getTime();
        Long windowMs = 24L * 60L * 60L * 1000L;
        if (Datetime.now().getTime() - lastInboundMs > windowMs) {
          return 'SKIP: WhatsApp 24h window closed';
        }
        TwilioWhatsAppClient.SendResult resultValue = TwilioWhatsAppClient.sendText(
          conversation.External_Participant_ID__c,
          replyText
        );
        sendStatus = resultValue.success ? 'Sent' : 'Failed';
        externalId = resultValue.externalMessageId;
        providerError = resultValue.errorMessage;
      } else {
        return 'SKIP: unsupported channel=' + conversation.Channel__c;
      }

      Message__c outgoing = new Message__c(
        Conversation__c = incoming.Conversation__c,
        Direction__c = 'Outgoing',
        Sender_Type__c = 'Agentforce',
        Channel__c = conversation.Channel__c,
        Status__c = sendStatus,
        Body__c = replyText.left(32768),
        External_Message_ID__c = externalId,
        Provider_Error__c = providerError,
        Sent_At__c = Datetime.now()
      );
      insert as system outgoing;

      if (sendStatus == 'Sent') {
        Conversation__c updateConv = new Conversation__c(
          Id = incoming.Conversation__c,
          Last_Outbound_At__c = Datetime.now(),
          Last_Message_At__c = Datetime.now(),
          Last_Message_Preview__c = replyText.left(255)
        );
        update as system updateConv;
      }

      return 'Sent sid=' + externalId + ' err=' + providerError;
    } catch (Exception exceptionValue) {
      String errorValue = exceptionValue.getTypeName() + ': ' + exceptionValue.getMessage();
      System.debug(
        LoggingLevel.ERROR,
        'AgentAutoRespondAction failed for ' + messageId + ': ' + errorValue + '\n' + exceptionValue.getStackTraceString()
      );
      return 'Error: ' + errorValue;
    }
  }
}
