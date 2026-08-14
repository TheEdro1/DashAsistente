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
      respondSilently(response);
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
      inbound.displayName = fixMojibake(profileName);
      inbound.externalMessageId = messageSid;
      inbound.body = String.isBlank(bodyValue)
        ? SMS_BODY_PLACEHOLDER
        : fixMojibake(bodyValue);
      inbound.sentAt = parseTimestamp(formParams.get('MessageTimestamp'));
      ConversationMessagingService.recordIncoming(inbound);
      respondSilently(response);
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
    Map<String, String> normalizedParams = normalizeParamsForTwilio(formParams);
    String expected = TwilioWhatsAppClient.buildSignature(
      authToken,
      fullUrl,
      normalizedParams
    );
    return secureEquals(expected, providedSignature);
  }

  private static Map<String, String> normalizeParamsForTwilio(
    Map<String, String> source
  ) {
    if (source == null) {
      return null;
    }
    Map<String, String> result = new Map<String, String>();
    for (String key : source.keySet()) {
      result.put(key, fixMojibake(source.get(key)));
    }
    return result;
  }

  private static String fixMojibake(String value) {
    if (value == null) {
      return null;
    }
    Boolean needsFix = false;
    for (Integer i = 0; i < value.length(); i++) {
      Integer cp = value.codePointAt(i);
      if (cp >= 128 && cp <= 255) {
        needsFix = true;
        break;
      }
    }
    if (!needsFix) {
      return value;
    }
    try {
      String hex = '';
      String digits = '0123456789ABCDEF';
      for (Integer i = 0; i < value.length(); i++) {
        Integer cp = value.codePointAt(i);
        Integer byteVal = cp & 255;
        Integer high = (byteVal >> 4) & 15;
        Integer low = byteVal & 15;
        hex += digits.substring(high, high + 1);
        hex += digits.substring(low, low + 1);
      }
      Blob bytes = EncodingUtil.convertFromHex(hex);
      return bytes.toString();
    } catch (Exception exceptionValue) {
      System.debug(
        'TwilioSig: fixMojibake failed: ' + exceptionValue.getMessage()
      );
      return value;
    }
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

  private static void respondSilently(RestResponse response) {
    response.statusCode = 200;
    response.addHeader('Content-Type', 'application/xml');
    response.responseBody = Blob.valueOf('<Response></Response>');
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
