/**
 * System-mode gateway shared by signed public webhooks, Email Services and the
 * permission-set-protected advisor controller. System mode is required because
 * guest and automation users don't receive normal object permissions.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ConversationMessagingService {
  private static final Integer MAX_BODY_LENGTH = 32768;
  private static final Long WHATSAPP_WINDOW_MS = 24L * 60L * 60L * 1000L;

  @TestVisible
  private static Boolean forceLeadResolutionUnavailable = false;

  public class InboundMessage {
    public String channel;
    public String participantId;
    public String displayName;
    public String externalMessageId;
    public String body;
    public String subject;
    public Datetime sentAt;
    public Id preferredConversationId;
  }

  public static Message__c sendMessage(
    Id conversationId,
    String body,
    String senderType
  ) {
    if (conversationId == null) {
      throw new AuraHandledException(
        'Selecciona una conversación antes de enviar.'
      );
    }
    String cleanBody = String.isBlank(body) ? null : body.trim();
    if (String.isBlank(cleanBody)) {
      throw new AuraHandledException('Escribe un mensaje antes de enviar.');
    }
    if (cleanBody.length() > MAX_BODY_LENGTH) {
      throw new AuraHandledException(
        'El mensaje supera el límite de 32,768 caracteres.'
      );
    }

    Conversation__c conversation = [
      SELECT
        Id,
        Lead__c,
        Lead__r.Email,
        Lead__r.Phone,
        Lead__r.MobilePhone,
        Channel__c,
        Status__c,
        External_Participant_ID__c,
        Email_Subject__c,
        Last_Inbound_At__c
      FROM Conversation__c
      WHERE Id = :conversationId
      LIMIT 1
    ];

    String resolvedSenderType = senderType == 'Agentforce'
      ? 'Agentforce'
      : 'Advisor';
    String participant = resolveParticipant(conversation);
    String status = 'Failed';
    String externalMessageId;
    String providerError;

    if (conversation.Channel__c == 'WhatsApp') {
      if (
        conversation.Last_Inbound_At__c == null ||
        Datetime.now().getTime() - conversation.Last_Inbound_At__c.getTime() >
        WHATSAPP_WINDOW_MS
      ) {
        providerError =
          'La ventana de atención de WhatsApp está cerrada. ' +
          'El prospecto debe escribir de nuevo o debes usar una plantilla aprobada.';
      } else {
        WhatsAppCloudApiClient.SendResult result = WhatsAppCloudApiClient.sendText(
          participant,
          cleanBody
        );
        status = result.success ? 'Sent' : 'Failed';
        externalMessageId = result.externalMessageId;
        providerError = result.errorMessage;
      }
    } else if (conversation.Channel__c == 'Email') {
      EmailChannelService.SendResult result = EmailChannelService.sendText(
        participant,
        conversation.Email_Subject__c,
        cleanBody,
        conversation.Id
      );
      status = result.success ? 'Sent' : 'Failed';
      externalMessageId = result.externalMessageId;
      providerError = result.errorMessage;
    } else {
      providerError =
        'El canal ' +
        conversation.Channel__c +
        ' todavía no tiene un adaptador de envío.';
    }

    if (String.isBlank(externalMessageId)) {
      externalMessageId = EmailChannelService.generatedId('local');
    }

    Datetime sentAt = Datetime.now();
    Message__c message = new Message__c(
      Conversation__c = conversation.Id,
      External_Message_ID__c = truncate(externalMessageId, 255),
      Direction__c = 'Outgoing',
      Sender_Type__c = resolvedSenderType,
      Body__c = cleanBody,
      Subject__c = conversation.Email_Subject__c,
      Sent_At__c = sentAt,
      Status__c = status,
      Channel__c = conversation.Channel__c,
      Provider_Error__c = truncate(providerError, 2000),
      Sender_Advisor__c = resolvedSenderType == 'Advisor'
        ? UserInfo.getUserId()
        : null
    );
    insert message;

    conversation.Last_Message_At__c = sentAt;
    conversation.Last_Outbound_At__c = sentAt;
    conversation.Last_Message_Preview__c = truncate(cleanBody, 255);
    if (resolvedSenderType == 'Advisor') {
      conversation.Status__c = 'Human';
      conversation.Assigned_Advisor__c = UserInfo.getUserId();
      conversation.Needs_Human_Attention__c = false;
    }
    update conversation;
    updateLeadActivity(
      conversation.Lead__c,
      conversation.Channel__c,
      cleanBody,
      sentAt,
      false
    );

    return [
      SELECT
        Id,
        Name,
        Conversation__c,
        External_Message_ID__c,
        Direction__c,
        Sender_Type__c,
        Body__c,
        Subject__c,
        Sent_At__c,
        Status__c,
        Channel__c,
        Provider_Error__c,
        Sender_Advisor__c,
        Sender_Advisor__r.Name,
        CreatedDate
      FROM Message__c
      WHERE Id = :message.Id
    ];
  }

  public static Message__c recordIncoming(InboundMessage inbound) {
    validateInbound(inbound);
    String externalMessageId = String.isBlank(inbound.externalMessageId)
      ? EmailChannelService.generatedId('inbound')
      : truncate(inbound.externalMessageId, 255);

    List<Message__c> duplicates = [
      SELECT Id
      FROM Message__c
      WHERE External_Message_ID__c = :externalMessageId
      LIMIT 1
    ];
    if (!duplicates.isEmpty()) {
      return duplicates[0];
    }

    Datetime sentAt = inbound.sentAt == null ? Datetime.now() : inbound.sentAt;
    Id leadId = findOrCreateLead(
      inbound.channel,
      inbound.participantId,
      inbound.displayName
    );
    Conversation__c conversation = resolveConversation(inbound, leadId);

    Message__c message = new Message__c(
      Conversation__c = conversation.Id,
      External_Message_ID__c = externalMessageId,
      Direction__c = 'Incoming',
      Sender_Type__c = 'Customer',
      Body__c = truncate(inbound.body, MAX_BODY_LENGTH),
      Subject__c = truncate(inbound.subject, 255),
      Sent_At__c = sentAt,
      Status__c = 'Received',
      Channel__c = inbound.channel
    );
    insert message;

    conversation.Last_Message_At__c = sentAt;
    conversation.Last_Inbound_At__c = sentAt;
    conversation.Last_Message_Preview__c = truncate(inbound.body, 255);
    conversation.External_Participant_ID__c = truncate(
      inbound.participantId,
      255
    );
    if (inbound.channel == 'Email' && !String.isBlank(inbound.subject)) {
      conversation.Email_Subject__c = truncate(
        removeConversationToken(inbound.subject),
        255
      );
    }
    update conversation;
    updateLeadActivity(leadId, inbound.channel, inbound.body, sentAt, true);
    publishInboundEvent(message, inbound);
    return message;
  }

  public static void updateDeliveryStatus(
    String externalMessageId,
    String providerStatus,
    String errorValue
  ) {
    if (String.isBlank(externalMessageId)) {
      return;
    }
    List<Message__c> messages = [
      SELECT Id, Status__c
      FROM Message__c
      WHERE External_Message_ID__c = :externalMessageId
      LIMIT 1
    ];
    if (messages.isEmpty()) {
      return;
    }
    messages[0].Status__c = mapProviderStatus(providerStatus);
    messages[0].Provider_Error__c = truncate(errorValue, 2000);
    update messages[0];
  }

  private static Conversation__c resolveConversation(
    InboundMessage inbound,
    Id leadId
  ) {
    if (!isLeadResolutionAvailable()) {
      return resolveConversationWithoutLead(inbound);
    }

    if (inbound.preferredConversationId != null) {
      List<Conversation__c> preferred = [
        SELECT Id, Lead__c, Channel__c, External_Participant_ID__c
        FROM Conversation__c
        WHERE Id = :inbound.preferredConversationId
        LIMIT 1
      ];
      if (!preferred.isEmpty()) {
        return preferred[0];
      }
    }

    String conversationKey = buildConversationKey(
      inbound.channel,
      inbound.participantId
    );
    List<Conversation__c> existing = [
      SELECT Id, Lead__c, Channel__c, External_Participant_ID__c
      FROM Conversation__c
      WHERE External_Conversation_ID__c = :conversationKey
      LIMIT 1
    ];
    if (existing.isEmpty() && leadId != null) {
      existing = [
        SELECT Id, Lead__c, Channel__c, External_Participant_ID__c
        FROM Conversation__c
        WHERE
          Lead__c = :leadId
          AND Channel__c = :inbound.channel
          AND Status__c != 'Closed'
        ORDER BY Last_Message_At__c DESC NULLS LAST
        LIMIT 1
      ];
    }
    if (!existing.isEmpty()) {
      Conversation__c conversation = existing[0];
      if (conversation.Lead__c == null && leadId != null) {
        conversation.Lead__c = leadId;
      }
      conversation.External_Participant_ID__c = truncate(
        inbound.participantId,
        255
      );
      update conversation;
      return conversation;
    }

    Conversation__c created = new Conversation__c(
      Lead__c = leadId,
      Channel__c = inbound.channel,
      External_Conversation_ID__c = conversationKey,
      External_Participant_ID__c = truncate(inbound.participantId, 255),
      Status__c = 'Bot',
      Needs_Human_Attention__c = false
    );
    insert created;
    return created;
  }

  private static Conversation__c resolveConversationWithoutLead(
    InboundMessage inbound
  ) {
    if (inbound.preferredConversationId != null) {
      List<Conversation__c> preferred = [
        SELECT Id, Channel__c, External_Participant_ID__c
        FROM Conversation__c
        WHERE Id = :inbound.preferredConversationId
        LIMIT 1
      ];
      if (!preferred.isEmpty()) {
        return preferred[0];
      }
    }

    String conversationKey = buildConversationKey(
      inbound.channel,
      inbound.participantId
    );
    Conversation__c conversation = new Conversation__c(
      Channel__c = inbound.channel,
      External_Conversation_ID__c = conversationKey,
      External_Participant_ID__c = truncate(inbound.participantId, 255)
    );
    // Upsert is both retry-safe and race-safe. It can resolve the unique
    // external key even when a Sites guest user can't query a record that is
    // owned by the site's default record owner.
    upsert conversation External_Conversation_ID__c;
    return conversation;
  }

  private static Id findOrCreateLead(
    String channel,
    String participant,
    String displayName
  ) {
    // Salesforce Sites guest licenses don't expose the Lead sObject. Keep the
    // signed webhook operational and let an authenticated advisor/automation
    // associate the conversation later.
    if (!isLeadResolutionAvailable()) {
      return null;
    }

    List<Lead> matches = new List<Lead>();
    if (channel == 'Email') {
      matches = [
        SELECT Id
        FROM Lead
        WHERE IsConverted = FALSE AND Email = :participant
        ORDER BY LastModifiedDate DESC
        LIMIT 1
      ];
    } else if (channel == 'WhatsApp') {
      String normalizedTarget = WhatsAppCloudApiClient.normalizePhone(
        participant
      );
      for (Lead candidate : [
        SELECT Id, Phone, MobilePhone
        FROM Lead
        WHERE IsConverted = FALSE AND (Phone != NULL OR MobilePhone != NULL)
        ORDER BY LastModifiedDate DESC
        LIMIT 500
      ]) {
        if (
          phoneMatches(normalizedTarget, candidate.MobilePhone) ||
          phoneMatches(normalizedTarget, candidate.Phone)
        ) {
          matches.add(candidate);
          break;
        }
      }
    }
    if (!matches.isEmpty()) {
      return matches[0].Id;
    }

    if (!MessagingConfig.getSettings().autoCreateLeads) {
      return null;
    }
    Lead created = new Lead(
      LastName = String.isBlank(displayName) ? participant : displayName,
      Company = 'Prospecto ' + channel
    );
    if (channel == 'Email') {
      created.Email = participant;
    } else if (channel == 'WhatsApp') {
      created.MobilePhone =
        '+' + WhatsAppCloudApiClient.normalizePhone(participant);
    }
    insert created;
    return created.Id;
  }

  private static Boolean isLeadResolutionAvailable() {
    return (!forceLeadResolutionUnavailable &&
    UserInfo.getUserType() != 'Guest' &&
    Schema.getGlobalDescribe().containsKey('Lead'));
  }

  private static void updateLeadActivity(
    Id leadId,
    String channel,
    String body,
    Datetime activityAt,
    Boolean incoming
  ) {
    if (leadId == null) {
      return;
    }
    Lead leadUpdate = new Lead(
      Id = leadId,
      Canal__c = channel == 'Email' ? 'Correo' : channel,
      Estado__c = incoming ? 'online' : 'waiting',
      En_Conversacion__c = true,
      Actividad_Actual__c = incoming
        ? 'Nuevo mensaje por ' + channel
        : 'Respuesta enviada por ' + channel,
      Ultima_Actividad__c = activityAt
    );
    Database.update(leadUpdate, false);
  }

  private static String resolveParticipant(Conversation__c conversation) {
    if (!String.isBlank(conversation.External_Participant_ID__c)) {
      return conversation.External_Participant_ID__c;
    }
    if (conversation.Lead__c == null) {
      return null;
    }
    if (conversation.Channel__c == 'Email') {
      return conversation.Lead__r.Email;
    }
    return String.isBlank(conversation.Lead__r.MobilePhone)
      ? conversation.Lead__r.Phone
      : conversation.Lead__r.MobilePhone;
  }

  private static void validateInbound(InboundMessage inbound) {
    if (
      inbound == null ||
      (inbound.channel != 'WhatsApp' &&
      inbound.channel != 'Email')
    ) {
      throw new MessagingException('Canal entrante no compatible.');
    }
    if (String.isBlank(inbound.participantId)) {
      throw new MessagingException(
        'El mensaje entrante no contiene un participante.'
      );
    }
    if (String.isBlank(inbound.body)) {
      inbound.body = '[Mensaje sin texto]';
    }
  }

  private static Boolean phoneMatches(String target, String candidateValue) {
    String candidate = WhatsAppCloudApiClient.normalizePhone(candidateValue);
    if (String.isBlank(target) || String.isBlank(candidate)) {
      return false;
    }
    if (target == candidate) {
      return true;
    }
    Integer comparisonLength = Math.min(
      10,
      Math.min(target.length(), candidate.length())
    );
    return target.right(comparisonLength) == candidate.right(comparisonLength);
  }

  private static String buildConversationKey(
    String channel,
    String participant
  ) {
    String cleanParticipant = channel == 'WhatsApp'
      ? WhatsAppCloudApiClient.normalizePhone(participant)
      : participant.trim().toLowerCase();
    return truncate(channel.toLowerCase() + ':' + cleanParticipant, 255);
  }

  private static String removeConversationToken(String subject) {
    return String.isBlank(subject)
      ? subject
      : subject.replaceFirst(
            '(?i)^[ ]*(re:[ ]*)?[\\[]DASH:[a-zA-Z0-9]{15,18}[\\]][ ]*',
            ''
          )
          .trim();
  }

  private static String mapProviderStatus(String providerStatus) {
    if (String.isBlank(providerStatus)) {
      return 'Sent';
    }
    Map<String, String> statuses = new Map<String, String>{
      'sent' => 'Sent',
      'delivered' => 'Delivered',
      'read' => 'Read',
      'failed' => 'Failed'
    };
    String resolved = statuses.get(providerStatus.toLowerCase());
    return resolved == null ? 'Sent' : resolved;
  }

  private static void publishInboundEvent(
    Message__c message,
    InboundMessage inbound
  ) {
    EventBus.publish(
      new Message_Received__e(
        Conversation_Id__c = String.valueOf(message.Conversation__c),
        Message_Id__c = String.valueOf(message.Id),
        Channel__c = inbound.channel,
        Participant_Id__c = truncate(inbound.participantId, 255),
        Body__c = truncate(inbound.body, 4000)
      )
    );
  }

  private static String truncate(String value, Integer maxLength) {
    if (value == null || value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }

  public class MessagingException extends Exception {
  }
}
