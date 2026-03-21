/**
 * FC_Memory - Manages an agent's conversational short-term memory.
 *
 * Stores the ordered list of FC_ChatMessage objects representing the conversation
 * between the agent and the LLM. Automatically trims the oldest non-system messages
 * when the buffer exceeds maxMessages, preserving system messages.
 *
 * Context injection from prior task outputs is supported via injectContext().
 *
 * @group ForceCrew
 */
public class FC_Memory {

    private static final Integer DEFAULT_MAX_MESSAGES = 50;

    private List<FC_ChatMessage> history;
    private Integer              maxMessages;

    public FC_Memory() {
        this.history     = new List<FC_ChatMessage>();
        this.maxMessages = DEFAULT_MAX_MESSAGES;
    }

    public FC_Memory(Integer maxMessages) {
        this.history     = new List<FC_ChatMessage>();
        this.maxMessages = maxMessages > 0 ? maxMessages : DEFAULT_MAX_MESSAGES;
    }

    // ─── Mutation ─────────────────────────────────────────────────────────────

    /**
     * Adds a message to the history.
     * Trims oldest non-system messages if maxMessages is exceeded.
     */
    public void add(FC_ChatMessage message) {
        history.add(message);
        trimIfNeeded();
    }

    /**
     * Clears all non-system messages from history.
     * System messages (the agent's system prompt) are always preserved.
     */
    public void clear() {
        List<FC_ChatMessage> systemMessages = new List<FC_ChatMessage>();
        for (FC_ChatMessage msg : history) {
            if (msg.role == FC_ChatMessage.ROLE_SYSTEM) {
                systemMessages.add(msg);
            }
        }
        history = systemMessages;
    }

    // ─── Context Injection ────────────────────────────────────────────────────

    /**
     * Injects a prior task's output as a user message into the conversation history.
     * This gives the agent awareness of relevant prior work without polluting the system prompt.
     *
     * @param contextLabel  Human-readable label for the source (e.g., task name)
     * @param contextContent The output content to inject
     */
    public void injectContext(String contextLabel, String contextContent) {
        if (String.isNotBlank(contextContent)) {
            add(FC_ChatMessage.user('Context from "' + contextLabel + '":\n' + contextContent));
        }
    }

    // ─── Access ───────────────────────────────────────────────────────────────

    /** Returns a copy of the full conversation history. */
    public List<FC_ChatMessage> getHistory() {
        return history.clone();
    }

    public Integer size() {
        return history.size();
    }

    public Boolean isEmpty() {
        return history.isEmpty();
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    private void trimIfNeeded() {
        if (history.size() <= maxMessages) return;

        List<FC_ChatMessage> systemMessages    = new List<FC_ChatMessage>();
        List<FC_ChatMessage> nonSystemMessages = new List<FC_ChatMessage>();

        for (FC_ChatMessage msg : history) {
            if (msg.role == FC_ChatMessage.ROLE_SYSTEM) {
                systemMessages.add(msg);
            } else {
                nonSystemMessages.add(msg);
            }
        }

        Integer toRemove = history.size() - maxMessages;
        for (Integer i = 0; i < toRemove && !nonSystemMessages.isEmpty(); i++) {
            nonSystemMessages.remove(0);
        }

        history = new List<FC_ChatMessage>();
        history.addAll(systemMessages);
        history.addAll(nonSystemMessages);

        FC_Logger.debug('FC_Memory', 'Trimmed ' + toRemove + ' old messages from history.');
    }
}
