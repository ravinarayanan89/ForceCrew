/**
 * FC_ModelsAPIService - Salesforce Models API wrapper for ForceCrew.
 *
 * Encapsulates all communication with the native aiplatform.ModelsAPI.
 * No Named Credentials or HTTP callouts are required — this uses the built-in
 * Salesforce LLM platform service available in Einstein-enabled orgs.
 *
 * Default model: sfdc_ai__DefaultGPT4Omni
 * Override via constructor or FC_Agent.Builder.llmModel().
 *
 * @group ForceCrew
 */
public with sharing class FC_ModelsAPIService {

    public static final String MODEL_GPT4O       = 'sfdc_ai__DefaultGPT4Omni';
    public static final String MODEL_GPT4O_MINI  = 'sfdc_ai__DefaultGPT4OmniMini';
    public static final String MODEL_CLAUDE      = 'sfdc_ai__DefaultClaude';

    private String model;

    public FC_ModelsAPIService() {
        this.model = MODEL_GPT4O;
    }

    public FC_ModelsAPIService(String model) {
        this.model = String.isNotBlank(model) ? model : MODEL_GPT4O;
    }

    // ─── Chat ─────────────────────────────────────────────────────────────────

    /**
     * Sends a multi-turn chat request to the Salesforce Models API.
     *
     * @param messages Ordered list of FC_ChatMessage (system, user, assistant turns)
     * @return ChatResponse with content, generationId, and success/error info
     */
    public ChatResponse chat(List<FC_ChatMessage> messages) {
        if (messages == null || messages.isEmpty()) {
            return chatFailure('No messages provided to the LLM');
        }

        try {
            aiplatform.ModelsAPI.createChatGenerations_Request request = buildRequest(messages);

            FC_Logger.debug(
                'FC_ModelsAPIService',
                'Sending ' + messages.size() + ' messages to model: ' + model
            );

            aiplatform.ModelsAPI.createChatGenerations_Response response =
                new aiplatform.ModelsAPI().createChatGenerations(request);

            if (response?.Code200?.generationDetails?.generations == null
                || response.Code200.generationDetails.generations.isEmpty()) {
                return chatFailure('Models API returned an empty generations list');
            }

            String content      = response.Code200.generationDetails.generations[0].content;
            String generationId = response.Code200.generationDetails.generations[0].id;

            FC_Logger.debug('FC_ModelsAPIService', 'Response received [id=' + generationId + ']');

            return chatOk(content, generationId);

        } catch (aiplatform.ModelsAPI.createChatGenerations_ResponseException e) {
            String msg = 'Models API error [HTTP ' + e.responseCode + ']: ' + e.getMessage();
            FC_Logger.error('FC_ModelsAPIService', msg);
            return chatFailure(msg);
        } catch (Exception e) {
            String msg = 'Unexpected error calling Models API: ' + e.getMessage();
            FC_Logger.error('FC_ModelsAPIService', msg);
            return chatFailure(msg);
        }
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    private aiplatform.ModelsAPI.createChatGenerations_Request buildRequest(List<FC_ChatMessage> messages) {
        List<aiplatform.ModelsAPI_ChatMessageRequest> apiMessages =
            new List<aiplatform.ModelsAPI_ChatMessageRequest>();

        for (FC_ChatMessage msg : messages) {
            aiplatform.ModelsAPI_ChatMessageRequest apiMsg =
                new aiplatform.ModelsAPI_ChatMessageRequest();
            apiMsg.role    = msg.role;
            apiMsg.content = msg.content;
            apiMessages.add(apiMsg);
        }

        aiplatform.ModelsAPI_ChatGenerationsRequest body =
            new aiplatform.ModelsAPI_ChatGenerationsRequest();
        body.messages = apiMessages;

        aiplatform.ModelsAPI.createChatGenerations_Request request =
            new aiplatform.ModelsAPI.createChatGenerations_Request();
        request.modelName = model;
        request.body      = body;
        return request;
    }

    // ─── Response Factories ───────────────────────────────────────────────────

    private static ChatResponse chatOk(String content, String generationId) {
        ChatResponse r   = new ChatResponse();
        r.content        = content;
        r.generationId   = generationId;
        r.isSuccess      = true;
        return r;
    }

    private static ChatResponse chatFailure(String errorMsg) {
        ChatResponse r   = new ChatResponse();
        r.errorMessage   = errorMsg;
        r.isSuccess      = false;
        return r;
    }

    // ─── Response DTO ─────────────────────────────────────────────────────────

    public class ChatResponse {
        public String  content      { get; private set; }
        public String  generationId { get; private set; }
        public Boolean isSuccess    { get; private set; }
        public String  errorMessage { get; private set; }

        private ChatResponse() {}
    }
}
