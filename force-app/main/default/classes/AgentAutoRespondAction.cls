@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class AgentAutoRespondAction {
  private static final String CLIENT_AGENT_API_NAME = 'Asesor_Virtual_de_Seguros';

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
        'SELECT Id, Lead__c, Status__c, Channel__c, External_Participant_ID__c, Last_Inbound_At__c, ' +
        'Agent_Session_ID__c ' +
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
      if (conversation.Lead__c == null) {
        conversation = associateLead(conversation);
      }
      if (conversation.Status__c != 'Bot') {
        return 'SKIP: status=' + conversation.Status__c;
      }

      String promptBody = String.isBlank(incoming.Body__c)
        ? '[Mensaje sin texto - cliente envió adjunto]'
        : incoming.Body__c;
      ClientAgentResponse agentResponse = invokeClientAgent(
        promptBody,
        conversation.Agent_Session_ID__c
      );
      if (String.isBlank(agentResponse.text)) {
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
          agentResponse.text
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
        Body__c = agentResponse.text.left(32768),
        External_Message_ID__c = externalId,
        Provider_Error__c = providerError,
        Sent_At__c = Datetime.now()
      );
      insert as system outgoing;

      Conversation__c updateConv = new Conversation__c(
        Id = incoming.Conversation__c,
        Agent_Session_ID__c = agentResponse.sessionId
      );
      if (sendStatus == 'Sent') {
        updateConv.Last_Outbound_At__c = Datetime.now();
        updateConv.Last_Message_At__c = Datetime.now();
        updateConv.Last_Message_Preview__c = agentResponse.text.left(255);
      }
      update as system updateConv;

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

  private class ClientAgentResponse {
    String text;
    String sessionId;
  }

  private static Conversation__c associateLead(Conversation__c conversation) {
    String participant = conversation.External_Participant_ID__c;
    if (String.isBlank(participant)) {
      return conversation;
    }

    String targetPhone = TwilioWhatsAppClient.normalizePhone(participant);
    List<Lead> candidates = (List<Lead>) Database.queryWithBinds(
      'SELECT Id, Phone, MobilePhone ' +
      'FROM Lead ' +
      'WHERE IsConverted = FALSE AND (Phone != NULL OR MobilePhone != NULL) ' +
      'LIMIT 500',
      new Map<String, Object>(),
      AccessLevel.SYSTEM_MODE
    );
    Id leadId;
    for (Lead candidate : candidates) {
      if (
        phoneMatches(targetPhone, candidate.MobilePhone) ||
        phoneMatches(targetPhone, candidate.Phone)
      ) {
        leadId = candidate.Id;
        break;
      }
    }

    if (leadId == null && MessagingConfig.getSettings().autoCreateLeads) {
      Lead created = new Lead(
        LastName = participant,
        Company = 'Prospecto WhatsApp',
        MobilePhone = '+' + targetPhone,
        Canal__c = 'WhatsApp',
        En_Conversacion__c = true,
        Estado__c = 'online',
        Ultima_Actividad__c = Datetime.now()
      );
      insert as system created;
      leadId = created.Id;
    }

    if (leadId == null) {
      return conversation;
    }

    Conversation__c updateConversation = new Conversation__c(
      Id = conversation.Id,
      Lead__c = leadId
    );
    update as system updateConversation;
    conversation.Lead__c = leadId;
    return conversation;
  }

  private static Boolean phoneMatches(String target, String candidateValue) {
    String candidate = TwilioWhatsAppClient.normalizePhone(candidateValue);
    if (String.isBlank(target) || String.isBlank(candidate)) {
      return false;
    }
    if (target == candidate) {
      return true;
    }
    Integer comparisonLength = Math.min(
      10,
      Math.min(target.length(), candidate.length())
    );
    return target.right(comparisonLength) == candidate.right(comparisonLength);
  }

  private static ClientAgentResponse invokeClientAgent(
    String prompt,
    String sessionId
  ) {
    Invocable.Action action = Invocable.Action.createCustomAction(
      'generateAiAgentResponse',
      CLIENT_AGENT_API_NAME
    );
    action.setInvocationParameter('userMessage', prompt.trim());
    if (String.isNotBlank(sessionId)) {
      action.setInvocationParameter('sessionId', sessionId);
    }
    List<Invocable.Action.Result> results = action.invoke();
    if (results.isEmpty()) {
      throw new CalloutException('El agente cliente no devolvió respuesta.');
    }
    Invocable.Action.Result result = results[0];
    if (!result.isSuccess()) {
      String errors = String.valueOf(result.getErrors());
      throw new CalloutException('No fue posible consultar al agente cliente: ' + errors);
    }
    Map<String, Object> output = result.getOutputParameters();
    Object rawResponse = output == null ? null : output.get('agentResponse');
    if (rawResponse == null) {
      return new ClientAgentResponse();
    }
    String text = String.valueOf(rawResponse);
    if (text.startsWith('{')) {
      try {
        Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(text);
        if (envelope.containsKey('value')) {
          text = String.valueOf(envelope.get('value'));
        }
      } catch (Exception ignored) {
        // Keep the original response if not a JSON envelope.
      }
    }
    ClientAgentResponse response = new ClientAgentResponse();
    response.text = text;
    Object rawSessionId = output == null ? null : output.get('sessionId');
    response.sessionId = rawSessionId == null
      ? sessionId
      : String.valueOf(rawSessionId);
    return response;
  }
}
