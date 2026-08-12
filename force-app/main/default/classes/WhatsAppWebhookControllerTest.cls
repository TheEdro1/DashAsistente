@IsTest
private class WhatsAppWebhookControllerTest {
  @IsTest
  static void verifiesWebhookChallenge() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappVerifyToken = 'reto-hackaton-123';
    MessagingConfig.testSettings = settings;

    RestRequest request = new RestRequest();
    request.httpMethod = 'GET';
    request.requestUri = '/services/apexrest/messaging/whatsapp';
    request.params.put('hub.mode', 'subscribe');
    request.params.put('hub.verify_token', 'reto-hackaton-123');
    request.params.put('hub.challenge', '998877');
    RestContext.request = request;
    RestContext.response = new RestResponse();

    WhatsAppWebhookController.verifyWebhook();

    System.assertEquals(200, RestContext.response.statusCode);
    System.assertEquals('998877', RestContext.response.responseBody.toString());
  }

  @IsTest
  static void storesMessageAndStatusWebhook() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappEnabled = true;
    settings.requireWebhookSignature = false;
    MessagingConfig.testSettings = settings;
    insert new Lead(
      LastName = 'Webhook',
      Company = 'Demo',
      MobilePhone = '+52 55 9876 5432'
    );

    String body =
      '{"entry":[{"changes":[{"value":{' +
      '"contacts":[{"wa_id":"525598765432","profile":{"name":"Lead Webhook"}}],' +
      '"messages":[{"from":"525598765432","id":"wamid.WEBHOOK-1",' +
      '"timestamp":"1786500000","type":"text","text":{"body":"Necesito ayuda humana"}}]' +
      '}}]}]}';
    RestRequest request = new RestRequest();
    request.httpMethod = 'POST';
    request.requestUri = '/services/apexrest/messaging/whatsapp';
    request.requestBody = Blob.valueOf(body);
    RestContext.request = request;
    RestContext.response = new RestResponse();

    Test.startTest();
    WhatsAppWebhookController.receiveWebhook();
    Test.stopTest();

    System.assertEquals(200, RestContext.response.statusCode);
    Message__c received = [
      SELECT Body__c, Status__c, Direction__c, Conversation__r.Lead__c
      FROM Message__c
      WHERE External_Message_ID__c = 'wamid.WEBHOOK-1'
    ];
    System.assertEquals('Necesito ayuda humana', received.Body__c);
    System.assertEquals('Received', received.Status__c);
    System.assertEquals('Incoming', received.Direction__c);
    System.assertNotEquals(null, received.Conversation__r.Lead__c);
  }

  @IsTest
  static void rejectsUnsignedWebhookWhenRequired() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappEnabled = true;
    settings.requireWebhookSignature = true;
    settings.whatsappAppSecret = 'secret';
    MessagingConfig.testSettings = settings;

    RestRequest request = new RestRequest();
    request.httpMethod = 'POST';
    request.requestUri = '/services/apexrest/messaging/whatsapp';
    request.requestBody = Blob.valueOf('{}');
    RestContext.request = request;
    RestContext.response = new RestResponse();

    WhatsAppWebhookController.receiveWebhook();

    System.assertEquals(401, RestContext.response.statusCode);
  }

  @IsTest
  static void acceptsValidSignedWebhook() {
    MessagingConfig.Settings settings = new MessagingConfig.Settings();
    settings.whatsappEnabled = true;
    settings.requireWebhookSignature = true;
    settings.whatsappAppSecret = 'secret';
    MessagingConfig.testSettings = settings;

    Blob rawBody = Blob.valueOf('{"entry":[]}');
    String signature =
      'sha256=' +
      EncodingUtil.convertToHex(
        Crypto.generateMac('HmacSHA256', rawBody, Blob.valueOf('secret'))
      );
    RestRequest request = new RestRequest();
    request.httpMethod = 'POST';
    request.requestUri = '/services/apexrest/messaging/whatsapp';
    request.requestBody = rawBody;
    request.addHeader('x-hub-signature-256', signature);
    RestContext.request = request;
    RestContext.response = new RestResponse();

    WhatsAppWebhookController.receiveWebhook();

    System.assertEquals(200, RestContext.response.statusCode);
  }
}
