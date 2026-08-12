public without sharing class WhatsAppCloudApiClient {
  public class SendResult {
    public Boolean success;
    public String externalMessageId;
    public String errorMessage;
  }

  public static SendResult sendText(String recipient, String body) {
    MessagingConfig.Settings settings = MessagingConfig.getSettings();
    SendResult result = new SendResult();

    if (!settings.whatsappEnabled) {
      result.success = false;
      result.errorMessage = 'La integración de WhatsApp está desactivada.';
      return result;
    }

    if (
      String.isBlank(settings.whatsappNamedCredential) ||
      !Pattern.matches('^[A-Za-z0-9_]+$', settings.whatsappNamedCredential) ||
      String.isBlank(settings.whatsappGraphVersion) ||
      !Pattern.matches('^v[0-9]+[.][0-9]+$', settings.whatsappGraphVersion) ||
      String.isBlank(settings.whatsappPhoneNumberId) ||
      !Pattern.matches('^[0-9]+$', settings.whatsappPhoneNumberId)
    ) {
      result.success = false;
      result.errorMessage = 'La configuración de WhatsApp está incompleta.';
      return result;
    }

    String normalizedRecipient = normalizePhone(recipient);
    if (String.isBlank(normalizedRecipient)) {
      result.success = false;
      result.errorMessage = 'La conversación no tiene un número de WhatsApp válido.';
      return result;
    }

    HttpRequest request = new HttpRequest();
    request.setMethod('POST');
    request.setEndpoint(
      'callout:' +
        settings.whatsappNamedCredential +
        '/' +
        settings.whatsappGraphVersion +
        '/' +
        settings.whatsappPhoneNumberId +
        '/messages'
    );
    request.setHeader('Content-Type', 'application/json');
    request.setTimeout(20000);
    request.setBody(
      JSON.serialize(
        new Map<String, Object>{
          'messaging_product' => 'whatsapp',
          'recipient_type' => 'individual',
          'to' => normalizedRecipient,
          'type' => 'text',
          'text' => new Map<String, Object>{
            'preview_url' => false,
            'body' => body
          }
        }
      )
    );

    try {
      HttpResponse response = new Http().send(request);
      Map<String, Object> payload = parseObject(response.getBody());
      if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
        List<Object> messages = (List<Object>) payload.get('messages');
        if (messages != null && !messages.isEmpty()) {
          result.externalMessageId = String.valueOf(
            ((Map<String, Object>) messages[0]).get('id')
          );
        }
        result.success = !String.isBlank(result.externalMessageId);
        if (!result.success) {
          result.errorMessage = 'Meta aceptó la solicitud sin devolver un identificador de mensaje.';
        }
        return result;
      }

      result.success = false;
      result.errorMessage = extractError(payload, response.getStatusCode());
      return result;
    } catch (Exception exceptionValue) {
      result.success = false;
      result.errorMessage =
        'No fue posible conectar con WhatsApp: ' + exceptionValue.getMessage();
      return result;
    }
  }

  public static String normalizePhone(String phoneValue) {
    return String.isBlank(phoneValue)
      ? null
      : phoneValue.replaceAll('[^0-9]', '');
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
    Map<String, Object> errorValue = (Map<String, Object>) payload.get('error');
    if (errorValue != null && errorValue.get('message') != null) {
      return 'WhatsApp (' +
        statusCode +
        '): ' +
        String.valueOf(errorValue.get('message'));
    }
    return 'WhatsApp rechazó el mensaje con código HTTP ' + statusCode + '.';
  }
}
