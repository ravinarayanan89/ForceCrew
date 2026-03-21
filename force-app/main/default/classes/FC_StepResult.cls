/**
 * FC_StepResult - A single reasoning/action step captured during an agent's ReAct loop.
 * Records the thought, action type, tool invocation details, and results for observability.
 *
 * @group ForceCrew
 */
public class FC_StepResult {

    public enum StepType { TOOL_CALL, FINAL_ANSWER, ERROR }

    public StepType            stepType       { get; private set; }
    public String              thought        { get; private set; }
    public String              toolName       { get; private set; }
    public Map<String, Object> toolParameters { get; private set; }
    public String              toolResult     { get; private set; }
    public String              answer         { get; private set; }
    public String              rawLlmResponse { get; private set; }
    public Boolean             success        { get; private set; }
    public String              errorMessage   { get; private set; }

    private FC_StepResult() {
        this.success = false;
    }

    // ─── Factory Methods ──────────────────────────────────────────────────────

    public static FC_StepResult toolCall(
        String thought,
        String toolName,
        Map<String, Object> params,
        String result
    ) {
        FC_StepResult step   = new FC_StepResult();
        step.stepType        = StepType.TOOL_CALL;
        step.thought         = thought;
        step.toolName        = toolName;
        step.toolParameters  = params;
        step.toolResult      = result;
        step.success         = true;
        return step;
    }

    public static FC_StepResult finalAnswer(String thought, String answer) {
        FC_StepResult step = new FC_StepResult();
        step.stepType      = StepType.FINAL_ANSWER;
        step.thought       = thought;
        step.answer        = answer;
        step.success       = true;
        return step;
    }

    public static FC_StepResult error(String errorMessage, String rawResponse) {
        FC_StepResult step   = new FC_StepResult();
        step.stepType        = StepType.ERROR;
        step.errorMessage    = errorMessage;
        step.rawLlmResponse  = rawResponse;
        step.success         = false;
        return step;
    }

    public void setRawLlmResponse(String raw) {
        this.rawLlmResponse = raw;
    }
}
