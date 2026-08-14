public with sharing class AdvisorAssistantController {
  private static final String AGENT_API_NAME = 'Asistente_Financiero';

  public class AssistantResponse {
    @AuraEnabled
    public String text;
    @AuraEnabled
    public String sessionId;
  }

  @AuraEnabled
  public static AssistantResponse sendPrompt(String prompt, String sessionId) {
    if (String.isBlank(prompt)) {
      throw new AuraHandledException('Escribe un mensaje antes de enviar.');
    }
    return invokeAgent(prompt, sessionId, true);
  }

  public static AssistantResponse invokeAgentNonAura(
    String prompt,
    String sessionId
  ) {
    if (String.isBlank(prompt)) {
      throw new CalloutException('Escribe un mensaje antes de enviar.');
    }
    return invokeAgent(prompt, sessionId, false);
  }

  private static AssistantResponse invokeAgent(
    String prompt,
    String sessionId,
    Boolean auraContext
  ) {
    Invocable.Action action = Invocable.Action.createCustomAction(
      'generateAiAgentResponse',
      AGENT_API_NAME
    );
    action.setInvocationParameter('userMessage', prompt.trim());
    if (!String.isBlank(sessionId)) {
      action.setInvocationParameter('sessionId', sessionId);
    }

    List<Invocable.Action.Result> results = action.invoke();
    if (results.isEmpty()) {
      if (auraContext) {
        throw new AuraHandledException('El asistente no devolvió una respuesta.');
      }
      throw new CalloutException('El asistente no devolvió una respuesta.');
    }

    Invocable.Action.Result result = results[0];
    if (!result.isSuccess()) {
      if (auraContext) {
        throw new AuraHandledException('No fue posible consultar al asistente.');
      }
      throw new CalloutException('No fue posible consultar al asistente.');
    }

    Map<String, Object> output = result.getOutputParameters();
    AssistantResponse response = new AssistantResponse();
    response.text = extractText(output.get('agentResponse'));
    response.sessionId = (String) output.get('sessionId');
    return response;
  }

  private static String extractText(Object value) {
    if (value == null) {
      return null;
    }
    String text = String.valueOf(value);
    if (text.startsWith('{')) {
      try {
        Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(
          text
        );
        if (envelope.containsKey('value')) {
          return String.valueOf(envelope.get('value'));
        }
      } catch (Exception ignored) {
        // Keep the original response if the runtime returns plain text.
      }
    }
    return text;
  }
}
