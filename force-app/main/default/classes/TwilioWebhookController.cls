@RestResource(urlMapping='/messaging/twilio/*')
global without sharing class TwilioWebhookController {
  private static final String SMS_BODY_PLACEHOLDER = '[Mensaje sin texto]';

  @HttpPost
  global static void receiveWebhook() {
    RestRequest request = RestContext.request;
    RestResponse response = RestContext.response;
    MessagingConfig.Settings settings = MessagingConfig.getSettings();

    if (!settings.whatsappEnabled || settings.whatsappProvider != 'Twilio') {
      respond(response, 503, 'Twilio disabled');
      return;
    }

    Map<String, String> formParams = parseFormUrlEncoded(request.requestBody);
    if (formParams.isEmpty() && request.params != null) {
      formParams = new Map<String, String>();
      for (String key : request.params.keySet()) {
        formParams.put(key, request.params.get(key));
      }
    }
    String twilioSignature = headerValue(
      request.headers,
      'X-Twilio-Signature'
    );

    String fullUrl = buildFullUrl(request, settings.twilioWebhookPublicUrl);

    if (
      settings.requireWebhookSignature &&
      !isValidSignature(
        formParams,
        twilioSignature,
        settings.twilioAuthToken,
        fullUrl
      )
    ) {
      respond(response, 401, 'Invalid signature');
      return;
    }

    String messageStatus = formParams.get('MessageStatus');
    if (!String.isBlank(messageStatus)) {
      handleStatusCallback(formParams, messageStatus);
      respond(response, 200, 'STATUS_RECEIVED');
      return;
    }

    String fromValue = formParams.get('From');
    String bodyValue = formParams.get('Body');
    String messageSid = formParams.get('MessageSid');
    String profileName = formParams.get('ProfileName');

    if (String.isBlank(fromValue) || String.isBlank(messageSid)) {
      respond(response, 400, 'Missing From or MessageSid');
      return;
    }

    try {
      ConversationMessagingService.InboundMessage inbound = new ConversationMessagingService.InboundMessage();
      inbound.channel = 'WhatsApp';
      inbound.participantId = fromValue;
      inbound.displayName = profileName;
      inbound.externalMessageId = messageSid;
      inbound.body = String.isBlank(bodyValue) ? SMS_BODY_PLACEHOLDER : bodyValue;
      inbound.sentAt = parseTimestamp(formParams.get('MessageTimestamp'));
      ConversationMessagingService.recordIncoming(inbound);
      respond(response, 200, 'EVENT_RECEIVED');
    } catch (Exception exceptionValue) {
      System.debug(
        LoggingLevel.ERROR,
        'Twilio webhook error: ' + exceptionValue.getMessage()
      );
      respond(response, 500, 'Processing error');
    }
  }

  @TestVisible
  private static void handleStatusCallback(
    Map<String, String> formParams,
    String messageStatus
  ) {
    String messageSid = formParams.get('MessageSid');
    if (String.isBlank(messageSid)) {
      return;
    }
    String errorMessage = extractErrorMessage(formParams);
    ConversationMessagingService.updateDeliveryStatus(
      messageSid,
      messageStatus,
      errorMessage
    );
  }

  private static String extractErrorMessage(Map<String, String> formParams) {
    String errorCode = formParams.get('ErrorCode');
    String errorMessage = formParams.get('ErrorMessage');
    if (String.isBlank(errorCode) && String.isBlank(errorMessage)) {
      return null;
    }
    String combined = '';
    if (!String.isBlank(errorCode)) {
      combined += errorCode;
    }
    if (!String.isBlank(errorMessage)) {
      if (combined.length() > 0) {
        combined += ' - ';
      }
      combined += errorMessage;
    }
    return combined;
  }

  private static Map<String, String> parseFormUrlEncoded(Blob body) {
    Map<String, String> params = new Map<String, String>();
    if (body == null) {
      return params;
    }
    String bodyString = body.toString();
    if (String.isBlank(bodyString)) {
      return params;
    }
    for (String pair : bodyString.split('&')) {
      Integer equalsIndex = pair.indexOf('=');
      if (equalsIndex < 0) {
        continue;
      }
      String key = EncodingUtil.urlDecode(pair.substring(0, equalsIndex), 'UTF-8');
      String value = EncodingUtil.urlDecode(
        pair.substring(equalsIndex + 1),
        'UTF-8'
      );
      params.put(key, value);
    }
    return params;
  }

  private static Boolean isValidSignature(
    Map<String, String> formParams,
    String providedSignature,
    String authToken,
    String fullUrl
  ) {
    if (String.isBlank(authToken)) {
      return false;
    }
    if (String.isBlank(providedSignature)) {
      return false;
    }
    String expected = TwilioWhatsAppClient.buildSignature(
      authToken,
      fullUrl,
      formParams
    );
    return secureEquals(expected, providedSignature);
  }

  private static String buildFullUrl(
    RestRequest request,
    String configuredPublicUrl
  ) {
    if (String.isNotBlank(configuredPublicUrl)) {
      return configuredPublicUrl;
    }
    String scheme = request.headers != null
      ? headerValue(request.headers, 'X-Forwarded-Proto')
      : null;
    String host = request.headers != null
      ? headerValue(request.headers, 'Host')
      : null;
    if (String.isBlank(host)) {
      host = request.requestURI;
    }
    if (String.isBlank(scheme)) {
      scheme = 'https';
    }
    return scheme + '://' + host + request.requestURI;
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

  private static Datetime parseTimestamp(String value) {
    if (String.isBlank(value)) {
      return Datetime.now();
    }
    try {
      Long epochSeconds = Long.valueOf(value);
      return Datetime.newInstance(epochSeconds * 1000L);
    } catch (Exception ignored) {
      return Datetime.now();
    }
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
