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
      return stripQuotedReply(email.plainTextBody);
    }
    if (!String.isBlank(email.htmlBody)) {
      String readableHtml = email.htmlBody
        .replaceAll('(?i)<br\\s*/?>', '\n')
        .replaceAll('(?i)</(p|div|li|tr)>', '\n')
        .stripHtmlTags();
      return stripQuotedReply(readableHtml);
    }
    return '[Correo sin cuerpo]';
  }

  @TestVisible
  private static String stripQuotedReply(String body) {
    if (String.isBlank(body)) {
      return body;
    }

    String normalized = body.replace('\r\n', '\n').replace('\r', '\n');
    List<String> replyLines = new List<String>();
    for (String line : normalized.split('\n')) {
      String trimmedLine = line.trim();
      if (isQuotedReplyBoundary(trimmedLine, !replyLines.isEmpty())) {
        break;
      }
      replyLines.add(line);
    }

    while (
      !replyLines.isEmpty() && String.isBlank(replyLines[replyLines.size() - 1])
    ) {
      replyLines.remove(replyLines.size() - 1);
    }

    String cleanedReply = String.join(replyLines, '\n').trim();
    return String.isBlank(cleanedReply) ? body.trim() : cleanedReply;
  }

  private static Boolean isQuotedReplyBoundary(
    String line,
    Boolean hasReplyText
  ) {
    if (String.isBlank(line)) {
      return false;
    }

    String lowerLine = line.toLowerCase();
    if (
      line.startsWith('>') ||
      Pattern.matches('^_{5,}$', line) ||
      Pattern.matches('^-{5,}.*$', line) ||
      lowerLine == 'begin forwarded message:' ||
      lowerLine == 'inicio del mensaje reenviado:' ||
      (lowerLine.startsWith('on ') && lowerLine.contains('wrote:')) ||
      (lowerLine.startsWith('el ') && lowerLine.contains('escribi'))
    ) {
      return true;
    }

    return hasReplyText &&
      (lowerLine.startsWith('de:') ||
      lowerLine.startsWith('from:') ||
      lowerLine.startsWith('enviado:') ||
      lowerLine.startsWith('sent:') ||
      lowerLine.startsWith('para:') ||
      lowerLine.startsWith('to:') ||
      lowerLine.startsWith('asunto:') ||
      lowerLine.startsWith('subject:'));
  }

  private static String normalizeAddress(String addressValue) {
    return String.isBlank(addressValue)
      ? null
      : addressValue.trim().toLowerCase();
  }
}
