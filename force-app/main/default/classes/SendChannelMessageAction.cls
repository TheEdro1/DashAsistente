public with sharing class SendChannelMessageAction {
  public class Request {
    @InvocableVariable(required=true label='Conversation ID')
    public Id conversationId;

    @InvocableVariable(required=true label='Message')
    public String body;

    @InvocableVariable(label='Sender Type')
    public String senderType;
  }

  public class Result {
    @InvocableVariable(label='Queue Job ID')
    public Id jobId;
  }

  @InvocableMethod(
    label='Enviar mensaje al canal'
    description='Encola una respuesta de Agentforce o de un asesor para WhatsApp o correo.'
  )
  public static List<Result> send(List<Request> requests) {
    List<ConversationOutboundJob.Payload> payloads = new List<ConversationOutboundJob.Payload>();
    for (Request requestValue : requests) {
      payloads.add(
        new ConversationOutboundJob.Payload(
          requestValue.conversationId,
          requestValue.body,
          String.isBlank(requestValue.senderType)
            ? 'Agentforce'
            : requestValue.senderType
        )
      );
    }
    Id jobId = System.enqueueJob(new ConversationOutboundJob(payloads));
    List<Result> results = new List<Result>();
    for (Integer indexValue = 0; indexValue < requests.size(); indexValue++) {
      Result resultValue = new Result();
      resultValue.jobId = jobId;
      results.add(resultValue);
    }
    return results;
  }
}
