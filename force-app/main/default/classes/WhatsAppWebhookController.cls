@RestResource(urlMapping='/messaging/whatsapp/*')
global without sharing class WhatsAppWebhookController {
  @HttpGet
  global static void verifyWebhook() {
    RestRequest request = RestContext.request;
    RestResponse response = RestContext.response;
    MessagingConfig.Settings settings = MessagingConfig.getSettings();

    String mode = request.params.get('hub.mode');
    String token = request.params.get('hub.verify_token');
    String challenge = request.params.get('hub.challenge');
    if (
      mode == 'subscribe' &&
      !String.isBlank(settings.whatsappVerifyToken) &&
      secureEquals(token, settings.whatsappVerifyToken) &&
      !String.isBlank(challenge)
    ) {
      response.statusCode = 200;
      response.addHeader('Content-Type', 'text/plain');
      response.responseBody = Blob.valueOf(challenge);
      return;
    }

    response.statusCode = 403;
    response.addHeader('Content-Type', 'text/plain');
    response.responseBody = Blob.valueOf('Forbidden');
  }

  @HttpPost
  global static void receiveWebhook() {
    RestRequest request = RestContext.request;
    RestResponse response = RestContext.response;
    MessagingConfig.Settings settings = MessagingConfig.getSettings();
    Blob rawBody = request.requestBody == null
      ? Blob.valueOf('')
      : request.requestBody;

    if (!settings.whatsappEnabled) {
      respond(response, 503, 'WhatsApp disabled');
      return;
    }
    if (
      !isValidSignature(
        rawBody,
        headerValue(request.headers, 'X-Hub-Signature-256'),
        settings
      )
    ) {
      respond(response, 401, 'Invalid signature');
      return;
    }

    try {
      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        rawBody.toString()
      );
      processPayload(payload);
      respond(response, 200, 'EVENT_RECEIVED');
    } catch (Exception exceptionValue) {
      System.debug(
        LoggingLevel.ERROR,
        'WhatsApp webhook error: ' + exceptionValue.getMessage()
      );
      respond(response, 400, 'Invalid payload');
    }
  }

  @TestVisible
  private static void processPayload(Map<String, Object> payload) {
    for (Object entryValue : listValue(payload.get('entry'))) {
      Map<String, Object> entry = mapValue(entryValue);
      for (Object changeValue : listValue(entry.get('changes'))) {
        Map<String, Object> changeItem = mapValue(changeValue);
        Map<String, Object> value = mapValue(changeItem.get('value'));
        Map<String, String> contactNames = extractContactNames(value);

        for (Object messageValue : listValue(value.get('messages'))) {
          Map<String, Object> providerMessage = mapValue(messageValue);
          ConversationMessagingService.InboundMessage inbound = new ConversationMessagingService.InboundMessage();
          inbound.channel = 'WhatsApp';
          inbound.participantId = stringValue(providerMessage.get('from'));
          inbound.displayName = contactNames.get(inbound.participantId);
          inbound.externalMessageId = stringValue(providerMessage.get('id'));
          inbound.body = extractMessageBody(providerMessage);
          inbound.sentAt = parseTimestamp(providerMessage.get('timestamp'));
          ConversationMessagingService.recordIncoming(inbound);
        }

        for (Object statusValue : listValue(value.get('statuses'))) {
          Map<String, Object> providerStatus = mapValue(statusValue);
          ConversationMessagingService.updateDeliveryStatus(
            stringValue(providerStatus.get('id')),
            stringValue(providerStatus.get('status')),
            extractStatusError(providerStatus)
          );
        }
      }
    }
  }

  private static Map<String, String> extractContactNames(
    Map<String, Object> value
  ) {
    Map<String, String> names = new Map<String, String>();
    for (Object contactValue : listValue(value.get('contacts'))) {
      Map<String, Object> contact = mapValue(contactValue);
      Map<String, Object> profile = mapValue(contact.get('profile'));
      names.put(
        stringValue(contact.get('wa_id')),
        stringValue(profile.get('name'))
      );
    }
    return names;
  }

  private static String extractMessageBody(
    Map<String, Object> providerMessage
  ) {
    String messageType = stringValue(providerMessage.get('type'));
    if (messageType == 'text') {
      return stringValue(mapValue(providerMessage.get('text')).get('body'));
    }
    if (messageType == 'button') {
      return stringValue(mapValue(providerMessage.get('button')).get('text'));
    }
    if (messageType == 'interactive') {
      Map<String, Object> interactive = mapValue(
        providerMessage.get('interactive')
      );
      Map<String, Object> reply = interactive.containsKey('button_reply')
        ? mapValue(interactive.get('button_reply'))
        : mapValue(interactive.get('list_reply'));
      return stringValue(reply.get('title'));
    }
    return '[Mensaje de WhatsApp tipo ' + messageType + ']';
  }

  private static String extractStatusError(Map<String, Object> providerStatus) {
    List<Object> errors = listValue(providerStatus.get('errors'));
    if (errors.isEmpty()) {
      return null;
    }
    Map<String, Object> errorValue = mapValue(errors[0]);
    String title = stringValue(errorValue.get('title'));
    String message = stringValue(errorValue.get('message'));
    return String.isBlank(message) ? title : title + ': ' + message;
  }

  private static Datetime parseTimestamp(Object timestampValue) {
    if (
      timestampValue == null || String.isBlank(String.valueOf(timestampValue))
    ) {
      return Datetime.now();
    }
    return Datetime.newInstance(
      Long.valueOf(String.valueOf(timestampValue)) * 1000L
    );
  }

  private static Boolean isValidSignature(
    Blob rawBody,
    String providedSignature,
    MessagingConfig.Settings settings
  ) {
    if (!settings.requireWebhookSignature) {
      return true;
    }
    if (
      String.isBlank(settings.whatsappAppSecret) ||
      String.isBlank(providedSignature)
    ) {
      return false;
    }
    String expected =
      'sha256=' +
      EncodingUtil.convertToHex(
        Crypto.generateMac(
          'HmacSHA256',
          rawBody,
          Blob.valueOf(settings.whatsappAppSecret)
        )
      );
    return secureEquals(
      expected.toLowerCase(),
      providedSignature.toLowerCase()
    );
  }

  private static Boolean secureEquals(String leftValue, String rightValue) {
    if (
      leftValue == null ||
      rightValue == null ||
      leftValue.length() != rightValue.length()
    ) {
      return false;
    }
    String leftHash = EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(leftValue))
    );
    String rightHash = EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(rightValue))
    );
    return leftHash == rightHash;
  }

  private static void respond(
    RestResponse response,
    Integer statusCode,
    String body
  ) {
    response.statusCode = statusCode;
    response.addHeader('Content-Type', 'text/plain');
    response.responseBody = Blob.valueOf(body);
  }

  private static Map<String, Object> mapValue(Object value) {
    return value instanceof Map<String, Object>
      ? (Map<String, Object>) value
      : new Map<String, Object>();
  }

  private static List<Object> listValue(Object value) {
    return value instanceof List<Object>
      ? (List<Object>) value
      : new List<Object>();
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static String headerValue(
    Map<String, String> headers,
    String requestedName
  ) {
    if (headers == null) {
      return null;
    }
    for (String headerName : headers.keySet()) {
      if (headerName != null && headerName.equalsIgnoreCase(requestedName)) {
        return headers.get(headerName);
      }
    }
    return null;
  }
}
