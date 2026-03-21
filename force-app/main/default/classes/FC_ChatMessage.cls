/**
 * FC_ChatMessage - A single message in an agent's conversation history.
 * Maps to the aiplatform.ModelsAPI_ChatMessageRequest role/content structure.
 *
 * @group ForceCrew
 */
public class FC_ChatMessage {

    public static final String ROLE_SYSTEM    = 'system';
    public static final String ROLE_USER      = 'user';
    public static final String ROLE_ASSISTANT = 'assistant';

    public String role    { get; private set; }
    public String content { get; private set; }

    private FC_ChatMessage() {}

    public FC_ChatMessage(String role, String content) {
        this.role    = role;
        this.content = content;
    }

    // ─── Factory Methods ──────────────────────────────────────────────────────

    public static FC_ChatMessage system(String content) {
        return new FC_ChatMessage(ROLE_SYSTEM, content);
    }

    public static FC_ChatMessage user(String content) {
        return new FC_ChatMessage(ROLE_USER, content);
    }

    public static FC_ChatMessage assistant(String content) {
        return new FC_ChatMessage(ROLE_ASSISTANT, content);
    }
}
