public without sharing class TwilioWhatsAppClient {
  public class SendResult {
    public Boolean success;
    public String externalMessageId;
    public String errorMessage;
  }

  public static SendResult sendText(String recipient, String body) {
    return send(recipient, body, null);
  }

  public static SendResult sendTemplate(
    String recipient,
    String contentSid,
    Map<String, String> variables
  ) {
    return send(recipient, null, contentSid, variables);
  }

  public static SendResult send(
    String recipient,
    String body,
    String contentSid
  ) {
    return send(recipient, body, contentSid, null);
  }

  public static SendResult send(
    String recipient,
    String body,
    String contentSid,
    Map<String, String> variables
  ) {
    MessagingConfig.Settings settings = MessagingConfig.getSettings();
    SendResult result = new SendResult();

    if (!settings.whatsappEnabled) {
      result.success = false;
      result.errorMessage = 'La integración de WhatsApp está desactivada.';
      return result;
    }

    if (settings.whatsappProvider != 'Twilio') {
      result.success = false;
      result.errorMessage =
        'TwilioWhatsAppClient sólo se usa cuando el provider es Twilio. Actual: ' +
        settings.whatsappProvider;
      return result;
    }

    if (
      String.isBlank(settings.twilioAccountSid) ||
      !Pattern.matches('^AC[0-9a-fA-F]{32}$', settings.twilioAccountSid)
    ) {
      result.success = false;
      result.errorMessage = 'Falta el Account SID de Twilio (formato ACxxxx).';
      return result;
    }

    if (String.isBlank(settings.twilioAuthToken)) {
      result.success = false;
      result.errorMessage = 'Falta el Auth Token de Twilio.';
      return result;
    }

    if (
      String.isBlank(settings.twilioFromNumber) ||
      !Pattern.matches('^\\+[0-9]{8,15}$', settings.twilioFromNumber)
    ) {
      result.success = false;
      result.errorMessage =
        'El número "From" de Twilio debe tener formato +E.164 (ej. +14155238886).';
      return result;
    }

    Boolean useTemplate = !String.isBlank(contentSid);
    if (useTemplate) {
      if (!String.isBlank(body)) {
        result.success = false;
        result.errorMessage =
          'No puedes mezclar Body y ContentSid en la misma llamada.';
        return result;
      }
      if (!Pattern.matches('^HX[0-9a-fA-F]{32}$', contentSid)) {
        result.success = false;
        result.errorMessage =
          'El ContentSid de Twilio debe tener formato HX + 32 hex (ej. HXb5b62575e6e4ff6129ad7c8efe1f983e).';
        return result;
      }
    } else if (String.isBlank(body)) {
      result.success = false;
      result.errorMessage = 'Falta el cuerpo del mensaje.';
      return result;
    }

    String normalizedRecipient = normalizePhone(recipient);
    if (String.isBlank(normalizedRecipient)) {
      result.success = false;
      result.errorMessage = 'La conversación no tiene un número de WhatsApp válido.';
      return result;
    }

    String toAddress = 'whatsapp:+' + normalizedRecipient;
    String fromAddress = 'whatsapp:' + settings.twilioFromNumber;
    String bodyString;
    if (useTemplate) {
      bodyString =
        'To=' +
        EncodingUtil.urlEncode(toAddress, 'UTF-8') +
        '&From=' +
        EncodingUtil.urlEncode(fromAddress, 'UTF-8') +
        '&ContentSid=' +
        EncodingUtil.urlEncode(contentSid, 'UTF-8') +
        '&ContentVariables=' +
        EncodingUtil.urlEncode(
          JSON.serialize(variables == null ? new Map<String, String>() : variables),
          'UTF-8'
        );
    } else {
      bodyString =
        'To=' +
        EncodingUtil.urlEncode(toAddress, 'UTF-8') +
        '&From=' +
        EncodingUtil.urlEncode(fromAddress, 'UTF-8') +
        '&Body=' +
        EncodingUtil.urlEncode(body, 'UTF-8');
    }

    HttpRequest request = new HttpRequest();
    request.setMethod('POST');
    request.setEndpoint(
      'https://api.twilio.com/2010-04-01/Accounts/' +
        settings.twilioAccountSid +
        '/Messages.json'
    );
    request.setHeader(
      'Authorization',
      'Basic ' +
        EncodingUtil.base64Encode(
          Blob.valueOf(
            settings.twilioAccountSid + ':' + settings.twilioAuthToken
          )
        )
    );
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    request.setBody(bodyString);
    request.setTimeout(20000);

    try {
      HttpResponse response = new Http().send(request);
      Map<String, Object> payload = parseObject(response.getBody());
      if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
        result.externalMessageId = stringValue(payload.get('sid'));
        result.success = !String.isBlank(result.externalMessageId);
        if (!result.success) {
          result.errorMessage =
            'Twilio aceptó la solicitud sin devolver un SID de mensaje.';
        }
        return result;
      }
      result.success = false;
      result.errorMessage = extractError(payload, response.getStatusCode());
      return result;
    } catch (Exception exceptionValue) {
      result.success = false;
      result.errorMessage =
        'No fue posible conectar con Twilio: ' + exceptionValue.getMessage();
      return result;
    }
  }

  public static String normalizePhone(String phoneValue) {
    return String.isBlank(phoneValue)
      ? null
      : phoneValue.replaceAll('[^0-9]', '');
  }

  public static String buildSignature(
    String authToken,
    String fullUrl,
    Map<String, String> formParams
  ) {
    if (String.isBlank(authToken) || formParams == null) {
      return null;
    }
    List<String> sortedKeys = new List<String>(formParams.keySet());
    sortedKeys.sort();
    String signingString = fullUrl;
    for (String key : sortedKeys) {
      signingString += key + formParams.get(key);
    }
    return EncodingUtil.base64Encode(
      Crypto.generateMac(
        'HmacSHA1',
        Blob.valueOf(signingString),
        Blob.valueOf(authToken)
      )
    );
  }

  private static Map<String, Object> parseObject(String jsonValue) {
    if (String.isBlank(jsonValue)) {
      return new Map<String, Object>();
    }
    Object parsed = JSON.deserializeUntyped(jsonValue);
    return parsed instanceof Map<String, Object>
      ? (Map<String, Object>) parsed
      : new Map<String, Object>();
  }

  private static String extractError(
    Map<String, Object> payload,
    Integer statusCode
  ) {
    String topMessage = stringValue(payload.get('message'));
    if (!String.isBlank(topMessage)) {
      return 'Twilio (' + statusCode + '): ' + topMessage;
    }
    Object code = payload.get('code');
    if (code != null) {
      return 'Twilio rechazó el mensaje con código HTTP ' +
        statusCode +
        ' (código ' +
        code +
        ').';
    }
    return 'Twilio rechazó el mensaje con código HTTP ' + statusCode + '.';
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }
}
