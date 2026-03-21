/**
 * FC_TaskResult - The result of executing a single FC_Task by an FC_Agent.
 * Contains the output, execution steps, timing, and error information.
 *
 * @group ForceCrew
 */
public class FC_TaskResult {

    public String             taskName        { get; private set; }
    public String             taskDescription { get; private set; }
    public String             agentRole       { get; private set; }
    public String             output          { get; private set; }
    public Boolean            success         { get; private set; }
    public String             errorMessage    { get; private set; }
    public List<FC_StepResult> steps          { get; private set; }
    public Long               executionTimeMs { get; private set; }

    public FC_TaskResult(String taskName, String taskDescription, String agentRole) {
        this.taskName        = taskName;
        this.taskDescription = taskDescription;
        this.agentRole       = agentRole;
        this.steps           = new List<FC_StepResult>();
        this.success         = false;
    }

    public void complete(String output, Long executionTimeMs) {
        this.output          = output;
        this.success         = true;
        this.executionTimeMs = executionTimeMs;
    }

    public void fail(String errorMessage, Long executionTimeMs) {
        this.errorMessage    = errorMessage;
        this.success         = false;
        this.executionTimeMs = executionTimeMs;
    }

    public void addStep(FC_StepResult step) {
        this.steps.add(step);
    }

    /** Returns the number of tool calls made during this task. */
    public Integer toolCallCount() {
        Integer count = 0;
        for (FC_StepResult step : steps) {
            if (step.stepType == FC_StepResult.StepType.TOOL_CALL) {
                count++;
            }
        }
        return count;
    }
}
