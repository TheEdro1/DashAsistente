/** Sends email in system mode for advisors, Agentforce and Email Services. */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class EmailChannelService {
  public class SendResult {
    public Boolean success;
    public String externalMessageId;
    public String errorMessage;
  }

  public static SendResult sendText(
    String recipient,
    String subject,
    String body,
    Id conversationId
  ) {
    MessagingConfig.Settings settings = MessagingConfig.getSettings();
    SendResult result = new SendResult();

    if (!settings.emailEnabled) {
      result.success = false;
      result.errorMessage = 'La integración de correo está desactivada.';
      return result;
    }
    if (String.isBlank(recipient) || !recipient.contains('@')) {
      result.success = false;
      result.errorMessage = 'La conversación no tiene un correo electrónico válido.';
      return result;
    }

    String resolvedSubject = String.isBlank(subject)
      ? settings.defaultEmailSubject
      : subject.trim();
    String conversationToken = '[DASH:' + String.valueOf(conversationId) + '] ';
    if (!resolvedSubject.startsWith(conversationToken)) {
      resolvedSubject = conversationToken + resolvedSubject;
    }

    Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
    emailMessage.setToAddresses(new List<String>{ recipient.trim() });
    emailMessage.setSubject(resolvedSubject);
    emailMessage.setPlainTextBody(body);
    emailMessage.setSenderDisplayName('Asesor IA');
    emailMessage.setSaveAsActivity(false);
    if (!String.isBlank(settings.emailFromAddress)) {
      List<OrgWideEmailAddress> senderAddresses = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE Address = :settings.emailFromAddress
        LIMIT 1
      ];
      if (!senderAddresses.isEmpty()) {
        emailMessage.setOrgWideEmailAddressId(senderAddresses[0].Id);
      }
    }
    if (!String.isBlank(settings.emailServiceAddress)) {
      emailMessage.setReplyTo(settings.emailServiceAddress.trim());
    }

    try {
      Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
        new List<Messaging.SingleEmailMessage>{ emailMessage },
        false
      );
      Messaging.SendEmailResult sendResult = sendResults.isEmpty()
        ? null
        : sendResults[0];
      result.success = sendResult != null && sendResult.isSuccess();
      result.externalMessageId = result.success
        ? generatedId('email-out')
        : null;
      if (!result.success) {
        result.errorMessage = firstEmailError(sendResult);
      }
      return result;
    } catch (Exception exceptionValue) {
      result.success = false;
      result.errorMessage =
        'No fue posible enviar el correo: ' + exceptionValue.getMessage();
      return result;
    }
  }

  public static String generatedId(String prefix) {
    return prefix + ':' + EncodingUtil.convertToHex(Crypto.generateAesKey(128));
  }

  private static String firstEmailError(Messaging.SendEmailResult result) {
    if (
      result != null &&
      result.getErrors() != null &&
      !result.getErrors().isEmpty()
    ) {
      return 'Correo: ' + result.getErrors()[0].getMessage();
    }
    return 'Salesforce no pudo enviar el correo.';
  }
}
