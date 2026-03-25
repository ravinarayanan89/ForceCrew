/**
 * FC_ModelsAPIService - Salesforce Models API wrapper for ForceCrew.
 *
 * Encapsulates all communication with the native aiplatform.ModelsAPI.
 * No Named Credentials or HTTP callouts are required — this uses the built-in
 * Salesforce LLM platform service available in Einstein-enabled orgs.
 *
 * Default model: sfdc_ai__DefaultBedrockAnthropicClaude45Opus (MODEL_DEFAULT)
 * Override via constructor or FC_Agent.Builder.llmModel().
 *
 * @group ForceCrew
 */
public with sharing class FC_ModelsAPIService {

    // ── OpenAI GPT (Geo-aware) ───────────────────────────────────────────────
    public static final String MODEL_GPT4O            = 'sfdc_ai__DefaultGPT4Omni';
    public static final String MODEL_GPT4O_MINI       = 'sfdc_ai__DefaultGPT4OmniMini';
    public static final String MODEL_GPT41             = 'sfdc_ai__DefaultGPT41';
    public static final String MODEL_GPT41_MINI        = 'sfdc_ai__DefaultGPT41Mini';
    public static final String MODEL_GPT5              = 'sfdc_ai__DefaultGPT5';
    public static final String MODEL_GPT5_MINI         = 'sfdc_ai__DefaultGPT5Mini';
    public static final String MODEL_O3                = 'sfdc_ai__DefaultO3';
    public static final String MODEL_O4_MINI           = 'sfdc_ai__DefaultO4Mini';

    // ── Anthropic Claude on Amazon Bedrock (Trust Boundary) ─────────────────
    public static final String MODEL_CLAUDE_SONNET45   = 'sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet';
    public static final String MODEL_CLAUDE_SONNET4    = 'sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet';
    public static final String MODEL_CLAUDE_OPUS45     = 'sfdc_ai__DefaultBedrockAnthropicClaude45Opus';
    public static final String MODEL_CLAUDE_HAIKU45    = 'sfdc_ai__DefaultBedrockAnthropicClaude45Haiku';

    // ── Google Gemini on Vertex AI ───────────────────────────────────────────
    public static final String MODEL_GEMINI3_PRO       = 'sfdc_ai__DefaultVertexAIGeminiPro30';
    public static final String MODEL_GEMINI3_FLASH     = 'sfdc_ai__DefaultVertexAIGemini30Flash';
    public static final String MODEL_GEMINI25_PRO      = 'sfdc_ai__DefaultVertexAIGeminiPro25';
    public static final String MODEL_GEMINI25_FLASH    = 'sfdc_ai__DefaultVertexAIGemini25Flash001';
    public static final String MODEL_GEMINI25_FLASH_LITE = 'sfdc_ai__DefaultVertexAIGemini25FlashLite001';

    // ── Amazon Nova on Bedrock ───────────────────────────────────────────────
    public static final String MODEL_NOVA_PRO          = 'sfdc_ai__DefaultBedrockAmazonNovaPro';
    public static final String MODEL_NOVA_LITE         = 'sfdc_ai__DefaultBedrockAmazonNovaLite';

    // ── Default ──────────────────────────────────────────────────────────────
    public static final String MODEL_DEFAULT           = MODEL_CLAUDE_OPUS45;

    // ─── Test Seam ────────────────────────────────────────────────────────────
    // Queued mock responses consumed by chat() during @IsTest execution.
    // Tests call enqueueMock() / enqueueMockFailure() before triggering LLM calls.

    @TestVisible private static List<ChatResponse> mockResponses = new List<ChatResponse>();

    @TestVisible
    private static void enqueueMock(String content) {
        mockResponses.add(chatOk(content, 'mock-' + mockResponses.size()));
    }

    @TestVisible
    private static void enqueueMockFailure(String error) {
        mockResponses.add(chatFailure(error));
    }

    @TestVisible
    private static void clearMocks() {
        mockResponses.clear();
    }

    private String model;

    public FC_ModelsAPIService() {
        this.model = MODEL_DEFAULT;
    }

    public FC_ModelsAPIService(String model) {
        this.model = String.isNotBlank(model) ? model : MODEL_DEFAULT;
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

        // Test seam: return next queued mock instead of calling the real API
        if (Test.isRunningTest() && !mockResponses.isEmpty()) {
            return mockResponses.remove(0);
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
