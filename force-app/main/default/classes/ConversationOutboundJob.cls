public without sharing class ConversationOutboundJob implements Queueable, Database.AllowsCallouts {
  public class Payload {
    public Id conversationId;
    public String body;
    public String senderType;

    public Payload(Id conversationId, String body, String senderType) {
      this.conversationId = conversationId;
      this.body = body;
      this.senderType = senderType;
    }
  }

  private List<Payload> payloads;

  public ConversationOutboundJob(List<Payload> payloads) {
    this.payloads = payloads;
  }

  public void execute(QueueableContext context) {
    for (Payload payload : payloads) {
      ConversationMessagingService.sendMessage(
        payload.conversationId,
        payload.body,
        payload.senderType
      );
    }
  }
}
