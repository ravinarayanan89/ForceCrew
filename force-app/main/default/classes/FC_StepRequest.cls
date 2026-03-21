/**
 * FC_StepRequest - Serialisable state object passed between step-by-step executions.
 *
 * Used by FC_AgentExecutorStep to maintain conversation state across multiple
 * Apex transactions. Store this in a custom object or pass it from LWC between calls.
 *
 * Why this exists:
 *   Salesforce governor limits (especially the Models API per-transaction cap)
 *   prevent a full ReAct loop from running in a single transaction for complex tasks.
 *   Instead, the LWC (or Queueable) drives the loop: each step is one transaction,
 *   one LLM call, one tool call — then state is serialised and returned.
 *
 * @group ForceCrew
 */
public class FC_StepRequest {

    /** Serialised conversation history — JSON array of {role, content} objects. */
    @AuraEnabled public String  historyJson    { get; set; }

    /** The agent's role (used to look up the agent from the crew config). */
    @AuraEnabled public String  agentRole      { get; set; }

    /** The task name currently being executed. */
    @AuraEnabled public String  taskName       { get; set; }

    /** True if the previous step reached FINAL_ANSWER — loop is complete. */
    @AuraEnabled public Boolean isComplete     { get; set; }

    /** The final answer text when isComplete = true. */
    @AuraEnabled public String  finalAnswer    { get; set; }

    /** Current iteration count (to enforce maxIterations across calls). */
    @AuraEnabled public Integer iterationCount { get; set; }

    /** Max iterations allowed (from the agent config). */
    @AuraEnabled public Integer maxIterations  { get; set; }

    /** Error message if the step failed. */
    @AuraEnabled public String  errorMessage   { get; set; }

    /** The FC_StepResult from the most recent step (JSON-serialised). */
    @AuraEnabled public String  lastStepJson   { get; set; }

    public FC_StepRequest() {
        this.isComplete     = false;
        this.iterationCount = 0;
        this.maxIterations  = 10;
    }

    // ─── History Helpers ──────────────────────────────────────────────────────

    /**
     * Deserialises historyJson back into a List<FC_ChatMessage> for use in an LLM call.
     */
    public List<FC_ChatMessage> getHistory() {
        if (String.isBlank(historyJson)) return new List<FC_ChatMessage>();

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(historyJson);
        List<FC_ChatMessage> messages = new List<FC_ChatMessage>();
        for (Object item : raw) {
            Map<String, Object> msg = (Map<String, Object>) item;
            messages.add(new FC_ChatMessage(
                (String) msg.get('role'),
                (String) msg.get('content')
            ));
        }
        return messages;
    }

    /**
     * Serialises a List<FC_ChatMessage> into historyJson for transport.
     */
    public void setHistory(List<FC_ChatMessage> messages) {
        List<Map<String, Object>> raw = new List<Map<String, Object>>();
        for (FC_ChatMessage msg : messages) {
            raw.add(new Map<String, Object>{
                'role'    => msg.role,
                'content' => msg.content
            });
        }
        this.historyJson = JSON.serialize(raw);
    }
}
