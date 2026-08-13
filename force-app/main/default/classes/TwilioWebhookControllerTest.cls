@IsTest
private class TwilioWebhookControllerTest {
  @TestSetup
  static void setupData() {
    insert new Lead(
      FirstName = 'María',
      LastName = 'TwilioDemo',
      Company = 'Demo Twilio',
      MobilePhone = '+52 1 55 9876 5432',
      Email = 'twilio@example.com'
    );
  }

  @IsTest
  static void processesValidSignedWebhook() {
    enableTwilio();

    String fullUrl =
      'https://my-site.example.com/services/apexrest/messaging/twilio/';
    Map<String, String> params = new Map<String, String>{
      'From' => '+5215598765432',
      'To' => '+14155238886',
      'Body' => 'Hola desde Twilio',
      'MessageSid' => 'SMtwilio-test-1',
      'ProfileName' => 'María TwilioDemo',
      'MessageTimestamp' => String.valueOf(
        Math.floor((Datetime.now().getTime() / 1000))
      )
    };
    String signature = TwilioWhatsAppClient.buildSignature(
      'twilio-auth-token',
      fullUrl,
      params
    );

    String bodyString = buildFormBody(params);
    postTwilioRequest(bodyString, signature, 'my-site.example.com');

    Test.startTest();
    TwilioWebhookController.receiveWebhook();
    Test.stopTest();

    List<Message__c> messages = [
      SELECT Id, Body__c, Direction__c, Channel__c, Status__c,
        Conversation__r.Lead__c
      FROM Message__c
      WHERE External_Message_ID__c = 'SMtwilio-test-1'
    ];
    System.assertEquals(1, messages.size(), 'Twilio message should be stored');
    System.assertEquals('Hola desde Twilio', messages[0].Body__c);
    System.assertEquals('Incoming', messages[0].Direction__c);
    System.assertEquals('WhatsApp', messages[0].Channel__c);
    System.assertNotEquals(null, messages[0].Conversation__r.Lead__c);
    System.assertEquals(200, RestContext.response.statusCode);
  }

  @IsTest
  static void rejectsRequestWithInvalidSignature() {
    enableTwilio();
    String bodyString = buildFormBody(
      new Map<String, String>{
        'From' => '+5215598765432',
        'To' => '+14155238886',
        'Body' => 'Hola',
        'MessageSid' => 'SMbad'
      }
    );
    postTwilioRequest(bodyString, 'sha1=ffffffff', 'my-site.example.com');

    Test.startTest();
    TwilioWebhookController.receiveWebhook();
    Test.stopTest();

    System.assertEquals(401, RestContext.response.statusCode);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Message__c WHERE External_Message_ID__c = 'SMbad']
    );
  }

  @IsTest
  static void rejectsWhenProviderIsNotTwilio() {
    enableWhatsAppWithMeta();
    postTwilioRequest('From=%2B5215598765432&Body=Hola&MessageSid=SMmeta', 'sha1=ignored', 'my-site.example.com');

    Test.startTest();
    TwilioWebhookController.receiveWebhook();
    Test.stopTest();

    System.assertEquals(503, RestContext.response.statusCode);
  }

  @IsTest
  static void processesDeliveryStatusCallback() {
    enableTwilio();
    Lead leadValue = [
      SELECT Id
      FROM Lead
      WHERE Email = 'twilio@example.com'
      LIMIT 1
    ];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Human',
      External_Participant_ID__c = '+5215598765432',
      Last_Inbound_At__c = Datetime.now()
    );
    insert conversation;
    Message__c outbound = new Message__c(
      Conversation__c = conversation.Id,
      External_Message_ID__c = 'SMoutbound-status-test',
      Direction__c = 'Outgoing',
      Sender_Type__c = 'Agentforce',
      Channel__c = 'WhatsApp',
      Body__c = 'Hola',
      Status__c = 'Sent',
      Sent_At__c = Datetime.now()
    );
    insert outbound;

    Map<String, String> params = new Map<String, String>{
      'MessageSid' => 'SMoutbound-status-test',
      'MessageStatus' => 'delivered',
      'To' => 'whatsapp:+5215598765432',
      'From' => 'whatsapp:+14155238886'
    };
    String signature = TwilioWhatsAppClient.buildSignature(
      'twilio-auth-token',
      'https://my-site.example.com/services/apexrest/messaging/twilio/',
      params
    );
    postTwilioRequest(buildFormBody(params), signature, 'my-site.example.com');

    Test.startTest();
    TwilioWebhookController.receiveWebhook();
    Test.stopTest();

    Message__c refreshed = [
      SELECT Status__c, Provider_Error__c
      FROM Message__c
      WHERE External_Message_ID__c = 'SMoutbound-status-test'
    ];
    System.assertEquals('Delivered', refreshed.Status__c);
    System.assertEquals(200, RestContext.response.statusCode);
  }

  @IsTest
  static void processesFailedStatusCallback() {
    enableTwilio();
    Lead leadValue = [
      SELECT Id
      FROM Lead
      WHERE Email = 'twilio@example.com'
      LIMIT 1
    ];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Human',
      External_Participant_ID__c = '+5215598765432',
      Last_Inbound_At__c = Datetime.now()
    );
    insert conversation;
    insert new Message__c(
      Conversation__c = conversation.Id,
      External_Message_ID__c = 'SMoutbound-failed',
      Direction__c = 'Outgoing',
      Sender_Type__c = 'Agentforce',
      Channel__c = 'WhatsApp',
      Body__c = 'Hola',
      Status__c = 'Sent',
      Sent_At__c = Datetime.now()
    );

    Map<String, String> params = new Map<String, String>{
      'MessageSid' => 'SMoutbound-failed',
      'MessageStatus' => 'failed',
      'ErrorCode' => '63021',
      'ErrorMessage' => 'Recipient is not opted in to sandbox',
      'To' => 'whatsapp:+5215598765432'
    };
    String signature = TwilioWhatsAppClient.buildSignature(
      'twilio-auth-token',
      'https://my-site.example.com/services/apexrest/messaging/twilio/',
      params
    );
    postTwilioRequest(buildFormBody(params), signature, 'my-site.example.com');

    Test.startTest();
    TwilioWebhookController.receiveWebhook();
    Test.stopTest();

    Message__c refreshed = [
      SELECT Status__c, Provider_Error__c
      FROM Message__c
      WHERE External_Message_ID__c = 'SMoutbound-failed'
    ];
    System.assertEquals('Failed', refreshed.Status__c);
    System.assert(refreshed.Provider_Error__c.contains('63021'));
    System.assert(refreshed.Provider_Error__c.contains('Recipient'));
  }

  @IsTest
  static void sendsTwilioAndStoresSid() {
    enableTwilio();
    Test.setMock(HttpCalloutMock.class, new TwilioSuccessMock());
    Lead leadValue = [
      SELECT Id
      FROM Lead
      WHERE Email = 'twilio@example.com'
      LIMIT 1
    ];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Bot',
      External_Participant_ID__c = '+5215598765432',
      Last_Inbound_At__c = Datetime.now()
    );
    insert conversation;

    Test.startTest();
    Message__c sent = ConversationMessagingService.sendMessage(
      conversation.Id,
      'Respuesta automática de Twilio',
      'Agentforce'
    );
    Test.stopTest();

    System.assertEquals('Sent', sent.Status__c);
    System.assertEquals('SMoutbound-test-1', sent.External_Message_ID__c);
  }

  @IsTest
  static void sendsTemplateWithContentSidAndVariables() {
    enableTwilio();
    Test.setMock(HttpCalloutMock.class, new TwilioTemplateMock());
    Lead leadValue = [
      SELECT Id
      FROM Lead
      WHERE Email = 'twilio@example.com'
      LIMIT 1
    ];
    Conversation__c conversation = new Conversation__c(
      Lead__c = leadValue.Id,
      Channel__c = 'WhatsApp',
      Status__c = 'Bot',
      External_Participant_ID__c = '+5215598765432',
      Last_Inbound_At__c = Datetime.now()
    );
    insert conversation;

    Test.startTest();
    TwilioWhatsAppClient.SendResult result = TwilioWhatsAppClient.send(
      '+5215598765432',
      null,
      'HXb5b62575e6e4ff6129ad7c8efe1f983e',
      new Map<String, String>{ '1' => '12/1', '2' => '3pm' }
    );
    Test.stopTest();

    System.assert(result.success, 'Template send should succeed');
    System.assertEquals('MMtemplate-out-1', result.externalMessageId);
  }

  @IsTest
  static void rejectsMalformedContentSid() {
    enableTwilio();
    TwilioWhatsAppClient.SendResult result = TwilioWhatsAppClient.send(
      '+5215598765432',
      null,
      'NOT-A-VALID-SID',
      null
    );
    System.assertEquals(false, result.success);
    System.assert(result.errorMessage.contains('HX'));
  }

  @IsTest
  static void rejectsMixedBodyAndTemplate() {
    enableTwilio();
    TwilioWhatsAppClient.SendResult result = TwilioWhatsAppClient.send(
      '+5215598765432',
      'Hola',
      'HXb5b62575e6e4ff6129ad7c8efe1f983e',
      null
    );
    System.assertEquals(false, result.success);
    System.assert(result.errorMessage.contains('Body'));
  }

  private static void enableTwilio() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappEnabled = true;
    settings.whatsappProvider = 'Twilio';
    settings.twilioAccountSid = 'AC' + '0'.repeat(32);
    settings.twilioAuthToken = 'twilio-auth-token';
    settings.twilioFromNumber = '+14155238886';
    settings.requireWebhookSignature = true;
    settings.autoCreateLeads = false;
    MessagingConfig.testSettings = settings;
  }

  private static void enableWhatsAppWithMeta() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappEnabled = true;
    settings.whatsappProvider = 'Meta';
    settings.whatsappNamedCredential = 'WhatsApp_Graph';
    settings.whatsappGraphVersion = 'v24.0';
    settings.whatsappPhoneNumberId = '123456';
    settings.requireWebhookSignature = true;
    MessagingConfig.testSettings = settings;
  }

  private static String buildFormBody(Map<String, String> params) {
    String bodyString = '';
    List<String> keys = new List<String>(params.keySet());
    keys.sort();
    for (String key : keys) {
      if (bodyString.length() > 0) {
        bodyString += '&';
      }
      bodyString += key + '=' + EncodingUtil.urlEncode(params.get(key), 'UTF-8');
    }
    return bodyString;
  }

  private static void postTwilioRequest(
    String bodyString,
    String signature,
    String host
  ) {
    RestRequest request = new RestRequest();
    request.requestURI = '/services/apexrest/messaging/twilio/';
    request.httpMethod = 'POST';
    request.requestBody = Blob.valueOf(bodyString);
    request.addHeader('Content-Type', 'application/x-www-form-urlencoded');
    request.addHeader('Host', host);
    request.addHeader('X-Forwarded-Proto', 'https');
    if (String.isNotBlank(signature)) {
      request.addHeader('X-Twilio-Signature', signature);
    }
    RestContext.request = request;
    RestContext.response = new RestResponse();
  }

  private class TwilioSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('POST', request.getMethod());
      System.assert(
        request.getEndpoint().contains(
          '/Accounts/AC00000000000000000000000000000000/Messages.json'
        ),
        'Endpoint should target Twilio Messages.json'
      );
      System.assert(
        request.getBody().contains('To=whatsapp%3A%2B5215598765432'),
        'To should include whatsapp: prefix and +E164: ' + request.getBody()
      );
      System.assert(
        request.getBody().contains('From=whatsapp%3A%2B14155238886'),
        'From should include whatsapp: prefix and +E164: ' + request.getBody()
      );
      System.assert(
        request.getBody().contains('Body='),
        'Plain text send should include Body parameter'
      );
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(
        '{"sid":"SMoutbound-test-1","status":"queued","to":"whatsapp:+5215598765432","from":"whatsapp:+14155238886"}'
      );
      return response;
    }
  }

  private class TwilioTemplateMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assert(
        request.getBody().contains('ContentSid=HXb5b62575e6e4ff6129ad7c8efe1f983e'),
        'Body should include ContentSid'
      );
      System.assert(
        request.getBody().contains('ContentVariables='),
        'Body should include ContentVariables'
      );
      System.assert(
        request.getBody().contains('%221%22'),
        'Variables JSON should include key 1'
      );
      System.assertEquals(false, request.getBody().contains('Body='));
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(
        '{"sid":"MMtemplate-out-1","status":"queued","to":"whatsapp:+5215598765432","from":"whatsapp:+14155238886"}'
      );
      return response;
    }
  }
}
