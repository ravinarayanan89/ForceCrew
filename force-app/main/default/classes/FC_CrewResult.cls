/**
 * FC_CrewResult - The result of a full crew kickoff execution.
 * Aggregates all task results and provides the final synthesized output.
 *
 * @group ForceCrew
 */
public class FC_CrewResult {

    public String             crewName           { get; private set; }
    public String             finalOutput        { get; private set; }
    public Boolean            success            { get; private set; }
    public String             errorMessage       { get; private set; }
    public List<FC_TaskResult> taskResults       { get; private set; }
    public Long               totalExecutionTimeMs { get; private set; }

    public FC_CrewResult(String crewName) {
        this.crewName     = crewName;
        this.taskResults  = new List<FC_TaskResult>();
        this.success      = false;
    }

    public void complete(String finalOutput, Long executionTimeMs) {
        this.finalOutput           = finalOutput;
        this.success               = true;
        this.totalExecutionTimeMs  = executionTimeMs;
    }

    public void fail(String errorMessage, Long executionTimeMs) {
        this.errorMessage          = errorMessage;
        this.success               = false;
        this.totalExecutionTimeMs  = executionTimeMs;
    }

    public void addTaskResult(FC_TaskResult taskResult) {
        this.taskResults.add(taskResult);
    }

    /**
     * Returns the output of the last successfully completed task.
     * This is typically used as the crew's final answer in sequential execution.
     */
    public String getLastTaskOutput() {
        for (Integer i = taskResults.size() - 1; i >= 0; i--) {
            if (taskResults[i].success) {
                return taskResults[i].output;
            }
        }
        return null;
    }

    /** Returns the total number of tool calls made across all tasks. */
    public Integer totalToolCalls() {
        Integer total = 0;
        for (FC_TaskResult tr : taskResults) {
            total += tr.toolCallCount();
        }
        return total;
    }

    /** Returns the number of tasks that completed successfully. */
    public Integer successfulTaskCount() {
        Integer count = 0;
        for (FC_TaskResult tr : taskResults) {
            if (tr.success) count++;
        }
        return count;
    }
}
