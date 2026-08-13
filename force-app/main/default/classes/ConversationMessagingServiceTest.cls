@IsTest
private class ConversationMessagingServiceTest {
  private class WhatsAppSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('POST', request.getMethod());
      System.assert(request.getEndpoint().endsWith('/v24.0/123456/messages'));
      System.assert(request.getBody().contains('5215512345678'));
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');
      response.setBody('{"messages":[{"id":"wamid.TEST-1"}]}');
      return response;
    }
  }

  @TestSetup
  static void setupData() {
    insert new Lead(
      FirstName = 'María',
      LastName = 'Prueba',
      Company = 'Demo',
      MobilePhone = '+52 1 55 1234 5678',
      Email = 'maria@example.com'
    );
  }

  @IsTest
  static void sendsWhatsAppAndStoresProviderId() {
    enableWhatsApp();
    Test.setMock(HttpCalloutMock.class, new WhatsAppSuccessMock());
    Lead leadValue = [SELECT Id FROM Lead WHERE Email = 'maria@example.com'];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Human',
      External_Conversation_ID__c = 'whatsapp:5215512345678',
      External_Participant_ID__c = '5215512345678',
      Last_Inbound_At__c = Datetime.now()
    );
    insert conversation;

    Test.startTest();
    Message__c sent = ConversationController.sendMessage(
      conversation.Id,
      'Hola desde Dash'
    );
    Test.stopTest();

    System.assertEquals('Sent', sent.Status__c);
    System.assertEquals('wamid.TEST-1', sent.External_Message_ID__c);
    System.assertEquals('Outgoing', sent.Direction__c);
    Conversation__c refreshed = [
      SELECT Last_Message_Preview__c, Last_Outbound_At__c
      FROM Conversation__c
      WHERE Id = :conversation.Id
    ];
    System.assertEquals('Hola desde Dash', refreshed.Last_Message_Preview__c);
    System.assertNotEquals(null, refreshed.Last_Outbound_At__c);
  }

  @IsTest
  static void blocksFreeFormWhatsAppOutsideServiceWindow() {
    enableWhatsApp();
    Lead leadValue = [SELECT Id FROM Lead WHERE Email = 'maria@example.com'];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Human',
      External_Participant_ID__c = '5215512345678',
      Last_Inbound_At__c = Datetime.now().addHours(-25)
    );
    insert conversation;

    Test.startTest();
    Message__c sent = ConversationMessagingService.sendMessage(
      conversation.Id,
      'Mensaje fuera de ventana',
      'Advisor'
    );
    Test.stopTest();

    System.assertEquals('Failed', sent.Status__c);
    System.assert(sent.Provider_Error__c.contains('ventana de atención'));
  }

  @IsTest
  static void recordsAndDeduplicatesInboundWhatsApp() {
    enableWhatsApp();
    ConversationMessagingService.InboundMessage inbound = new ConversationMessagingService.InboundMessage();
    inbound.channel = 'WhatsApp';
    inbound.participantId = '5215512345678';
    inbound.displayName = 'María Prueba';
    inbound.externalMessageId = 'wamid.IN-1';
    inbound.body = 'Quiero información de un seguro';
    inbound.sentAt = Datetime.now();

    Test.startTest();
    Message__c firstMessage = ConversationMessagingService.recordIncoming(
      inbound
    );
    Message__c duplicate = ConversationMessagingService.recordIncoming(inbound);
    Test.stopTest();

    System.assertEquals(firstMessage.Id, duplicate.Id);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Message__c
        WHERE External_Message_ID__c = 'wamid.IN-1'
      ]
    );
    Conversation__c conversation = [
      SELECT Lead__c, Last_Inbound_At__c, External_Participant_ID__c
      FROM Conversation__c
      WHERE Id = :firstMessage.Conversation__c
    ];
    System.assertNotEquals(null, conversation.Lead__c);
    System.assertNotEquals(null, conversation.Last_Inbound_At__c);
    System.assertEquals(
      '5215512345678',
      conversation.External_Participant_ID__c
    );
  }

  @IsTest
  static void recordsInboundWhenLeadIsUnavailable() {
    enableWhatsApp();
    ConversationMessagingService.forceLeadResolutionUnavailable = true;
    ConversationMessagingService.InboundMessage inbound = new ConversationMessagingService.InboundMessage();
    inbound.channel = 'WhatsApp';
    inbound.participantId = '5215550000000';
    inbound.displayName = 'Prospecto invitado';
    inbound.externalMessageId = 'wamid.GUEST-1';
    inbound.body = 'Mensaje recibido desde el sitio público';
    inbound.sentAt = Datetime.now();

    Test.startTest();
    Message__c received = ConversationMessagingService.recordIncoming(inbound);
    Test.stopTest();

    Conversation__c conversation = [
      SELECT Lead__c, External_Participant_ID__c, Last_Inbound_At__c
      FROM Conversation__c
      WHERE Id = :received.Conversation__c
    ];
    System.assertEquals(null, conversation.Lead__c);
    System.assertEquals(
      '5215550000000',
      conversation.External_Participant_ID__c
    );
    System.assertNotEquals(null, conversation.Last_Inbound_At__c);
  }

  @IsTest
  static void reusesConversationWhenLeadIsUnavailable() {
    enableWhatsApp();
    ConversationMessagingService.forceLeadResolutionUnavailable = true;
    Conversation__c existing = new Conversation__c(
      Channel__c = 'WhatsApp',
      External_Conversation_ID__c = 'whatsapp:5215551111111',
      External_Participant_ID__c = '5215551111111',
      Status__c = 'Human',
      Needs_Human_Attention__c = true
    );
    insert existing;

    ConversationMessagingService.InboundMessage inbound = new ConversationMessagingService.InboundMessage();
    inbound.channel = 'WhatsApp';
    inbound.participantId = '5215551111111';
    inbound.externalMessageId = 'wamid.GUEST-RETRY-1';
    inbound.body = 'Segundo mensaje del mismo prospecto';
    inbound.sentAt = Datetime.now();

    Test.startTest();
    Message__c received = ConversationMessagingService.recordIncoming(inbound);
    Test.stopTest();

    System.assertEquals(existing.Id, received.Conversation__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Conversation__c
        WHERE External_Conversation_ID__c = 'whatsapp:5215551111111'
      ]
    );
    Conversation__c unchanged = [
      SELECT Status__c, Needs_Human_Attention__c
      FROM Conversation__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals('Human', unchanged.Status__c);
    System.assertEquals(true, unchanged.Needs_Human_Attention__c);
  }

  @IsTest
  static void receivesEmailInExistingConversation() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.emailEnabled = true;
    MessagingConfig.testSettings = settings;
    Lead leadValue = [SELECT Id FROM Lead WHERE Email = 'maria@example.com'];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'Email',
      Status__c = 'Bot',
      External_Conversation_ID__c = 'email:maria@example.com',
      External_Participant_ID__c = 'maria@example.com'
    );
    insert conversation;

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.subject = 'Re: [DASH:' + conversation.Id + '] Seguro de vida';
    email.plainTextBody =
      'Gracias, quiero agendar una cita.\n\n' +
      '________________________________\n' +
      'De: Dashbot Asesor de Seguros <asesoria@example.com>\n' +
      'Enviado: jueves, 13 de agosto\n' +
      'Asunto: Seguro de vida\n' +
      'Texto anterior que no debe guardarse.';
    email.fromName = 'María Prueba';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
    envelope.fromAddress = 'MARIA@example.com';

    Test.startTest();
    Messaging.InboundEmailResult result = new InboundEmailChannelHandler()
      .handleInboundEmail(email, envelope);
    Test.stopTest();

    System.assertEquals(true, result.success);
    Message__c received = [
      SELECT Conversation__c, Channel__c, Direction__c, Body__c
      FROM Message__c
      WHERE Conversation__c = :conversation.Id
      LIMIT 1
    ];
    System.assertEquals('Email', received.Channel__c);
    System.assertEquals('Incoming', received.Direction__c);
    System.assertEquals('Gracias, quiero agendar una cita.', received.Body__c);
    System.assertEquals(
      'Respuesta breve desde Gmail',
      InboundEmailChannelHandler.stripQuotedReply(
        'Respuesta breve desde Gmail\n\n' +
          'El jue, 13 ago 2026 a la(s) 3:52 p.m., Dashbot Asesor de Seguros <eidanloz72@gmail.com> escribió:\n' +
          '> Mensaje anterior'
      )
    );

    Messaging.InboundEmail gmailEmail = new Messaging.InboundEmail();
    gmailEmail.plainTextBody =
      'PRUEBA_GMAIL_LIMPIA_001 El jue, 13 ago 2026 a la(s) 3:52 p.m., ' +
      'Dashbot Asesor de Seguros <eidanloz72@gmail.com> escribió: hola';
    gmailEmail.htmlBody =
      '<div dir="ltr">PRUEBA_GMAIL_LIMPIA_001</div><br>' +
      '<div class="gmail_quote gmail_quote_container">' +
      '<div class="gmail_attr">El jue, 13 ago 2026, Dashbot escribió:</div>' +
      '<blockquote>hola</blockquote></div>';
    System.assertEquals(
      'PRUEBA_GMAIL_LIMPIA_001',
      InboundEmailChannelHandler.resolveBody(gmailEmail)
    );
  }

  @IsTest
  static void sendsEmailAndStoresMessage() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.emailEnabled = true;
    settings.defaultEmailSubject = 'Seguro de vida';
    MessagingConfig.testSettings = settings;
    Lead leadValue = [SELECT Id FROM Lead WHERE Email = 'maria@example.com'];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'Email',
      Status__c = 'Human',
      External_Participant_ID__c = 'maria@example.com',
      Email_Subject__c = 'Seguro de vida'
    );
    insert conversation;

    Test.startTest();
    Message__c sent = ConversationMessagingService.sendMessage(
      conversation.Id,
      'Te comparto la información solicitada.',
      'Advisor'
    );
    Test.stopTest();

    System.assertEquals('Sent', sent.Status__c);
    System.assert(sent.External_Message_ID__c.startsWith('email-out:'));
    System.assertEquals('Email', sent.Channel__c);
    System.assertEquals(
      true,
      EmailChannelService.sameAddress(
        ' EIDANLOZ72@GMAIL.COM ',
        'eidanloz72@gmail.com'
      )
    );
    System.assertEquals(
      false,
      EmailChannelService.sameAddress(
        'ethandanloz722@gmail.com',
        'eidanloz72@gmail.com'
      )
    );
  }

  @IsTest
  static void agentforceActionQueuesChannelSend() {
    enableWhatsApp();
    Test.setMock(HttpCalloutMock.class, new WhatsAppSuccessMock());
    Lead leadValue = [SELECT Id FROM Lead WHERE Email = 'maria@example.com'];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Bot',
      External_Participant_ID__c = '5215512345678',
      Last_Inbound_At__c = Datetime.now()
    );
    insert conversation;
    SendChannelMessageAction.Request requestValue = new SendChannelMessageAction.Request();
    requestValue.conversationId = conversation.Id;
    requestValue.body = 'Respuesta automática de Agentforce';
    requestValue.senderType = 'Agentforce';

    Test.startTest();
    List<SendChannelMessageAction.Result> results = SendChannelMessageAction.send(
      new List<SendChannelMessageAction.Request>{ requestValue }
    );
    Test.stopTest();

    System.assertNotEquals(null, results[0].jobId);
    Message__c sent = [
      SELECT Sender_Type__c, Status__c
      FROM Message__c
      WHERE Conversation__c = :conversation.Id
      LIMIT 1
    ];
    System.assertEquals('Agentforce', sent.Sender_Type__c);
    System.assertEquals('Sent', sent.Status__c);
  }

  private static void enableWhatsApp() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappEnabled = true;
    settings.whatsappProvider = 'Meta';
    settings.whatsappNamedCredential = 'WhatsApp_Graph';
    settings.whatsappGraphVersion = 'v24.0';
    settings.whatsappPhoneNumberId = '123456';
    settings.requireWebhookSignature = false;
    MessagingConfig.testSettings = settings;
  }
}
