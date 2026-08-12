global without sharing class InboundEmailChannelHandler implements Messaging.InboundEmailHandler {
  global Messaging.InboundEmailResult handleInboundEmail(
    Messaging.InboundEmail email,
    Messaging.InboundEnvelope envelope
  ) {
    Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
    try {
      if (!MessagingConfig.getSettings().emailEnabled) {
        result.success = false;
        result.message = 'La integración de correo está desactivada.';
        return result;
      }

      ConversationMessagingService.InboundMessage inbound = new ConversationMessagingService.InboundMessage();
      inbound.channel = 'Email';
      inbound.participantId = normalizeAddress(envelope.fromAddress);
      inbound.displayName = email.fromName;
      inbound.externalMessageId = extractMessageId(email.headers);
      inbound.body = resolveBody(email);
      inbound.subject = email.subject;
      inbound.sentAt = Datetime.now();
      inbound.preferredConversationId = extractConversationId(email.subject);
      ConversationMessagingService.recordIncoming(inbound);
      result.success = true;
    } catch (Exception exceptionValue) {
      System.debug(
        LoggingLevel.ERROR,
        'Inbound email error: ' + exceptionValue.getMessage()
      );
      result.success = false;
      result.message = exceptionValue.getMessage();
    }
    return result;
  }

  @TestVisible
  private static Id extractConversationId(String subject) {
    if (String.isBlank(subject)) {
      return null;
    }
    Matcher matcherValue = Pattern.compile(
        '(?i)[\\[]DASH:([a-zA-Z0-9]{15,18})[\\]]'
      )
      .matcher(subject);
    if (!matcherValue.find()) {
      return null;
    }
    try {
      return (Id) matcherValue.group(1);
    } catch (Exception exceptionValue) {
      return null;
    }
  }

  private static String extractMessageId(
    List<Messaging.InboundEmail.Header> headers
  ) {
    if (headers != null) {
      for (Messaging.InboundEmail.Header headerValue : headers) {
        if (
          headerValue.name != null &&
          headerValue.name.toLowerCase() == 'message-id'
        ) {
          return 'email-in:' + headerValue.value;
        }
      }
    }
    return EmailChannelService.generatedId('email-in');
  }

  private static String resolveBody(Messaging.InboundEmail email) {
    if (!String.isBlank(email.plainTextBody)) {
      return email.plainTextBody.trim();
    }
    if (!String.isBlank(email.htmlBody)) {
      return email.htmlBody.stripHtmlTags().trim();
    }
    return '[Correo sin cuerpo]';
  }

  private static String normalizeAddress(String addressValue) {
    return String.isBlank(addressValue)
      ? null
      : addressValue.trim().toLowerCase();
  }
}
