/**
 * FC_Task - A unit of work assigned to an agent within a crew.
 * Use the Builder to construct immutable task instances.
 *
 * A task has a name, description, expected output, and an optional assigned agent role.
 * Tasks can declare dependencies on other tasks via withContext(), causing the output
 * of those prior tasks to be injected into this task's prompt automatically.
 *
 * Example:
 *   FC_Task dataTask = new FC_Task.Builder('Fetch Account Data')
 *       .description('Query the top 5 accounts by annual revenue using SOQL.')
 *       .expectedOutput('A JSON list of account names and their annual revenues.')
 *       .assignToAgent('Data Analyst')
 *       .build();
 *
 *   FC_Task reportTask = new FC_Task.Builder('Write Executive Summary')
 *       .description('Summarise the account data into a 3-bullet executive briefing.')
 *       .expectedOutput('Three concise bullet points highlighting key revenue insights.')
 *       .assignToAgent('Writer')
 *       .withContext('Fetch Account Data')   // receives output of dataTask as context
 *       .build();
 *
 * @group ForceCrew
 */
public class FC_Task {

    public String       name              { get; private set; }
    public String       description       { get; private set; }
    public String       expectedOutput    { get; private set; }
    public String       assignedAgentRole { get; private set; }
    public List<String> contextTaskNames  { get; private set; }

    private FC_Task() {}

    // ─── Builder ──────────────────────────────────────────────────────────────

    public class Builder {
        private FC_Task task;

        public Builder(String name) {
            if (String.isBlank(name)) {
                throw new FC_Exception.ConfigurationException('Task name cannot be blank');
            }
            task                  = new FC_Task();
            task.name             = name;
            task.contextTaskNames = new List<String>();
        }

        /**
         * A full description of what the agent should do for this task.
         * Be specific — the LLM uses this as its primary instruction.
         */
        public Builder description(String description) {
            task.description = description;
            return this;
        }

        /**
         * Describes the format and content of the expected output.
         * The LLM is instructed to match this specification in its FINAL_ANSWER.
         */
        public Builder expectedOutput(String expectedOutput) {
            task.expectedOutput = expectedOutput;
            return this;
        }

        /**
         * Assigns this task to a specific agent by role.
         * The role must match an agent registered in the crew.
         * If not set, the first agent in the crew is used.
         */
        public Builder assignToAgent(String agentRole) {
            task.assignedAgentRole = agentRole;
            return this;
        }

        /**
         * Declares that this task depends on the output of another task.
         * The named task's output will be injected into this task's prompt as context.
         * Multiple calls accumulate dependencies.
         *
         * @param taskName The exact name of the prior task whose output to include
         */
        public Builder withContext(String taskName) {
            if (String.isNotBlank(taskName)) {
                task.contextTaskNames.add(taskName);
            }
            return this;
        }

        /** Declares dependencies on multiple prior tasks at once. */
        public Builder withContextFrom(List<String> taskNames) {
            if (taskNames != null) {
                for (String n : taskNames) {
                    if (String.isNotBlank(n)) task.contextTaskNames.add(n);
                }
            }
            return this;
        }

        public FC_Task build() {
            if (String.isBlank(task.description)) {
                task.description = task.name;
            }
            if (String.isBlank(task.expectedOutput)) {
                task.expectedOutput = 'A complete and accurate response to the task.';
            }
            return task;
        }
    }

    // ─── Prompt Builder ───────────────────────────────────────────────────────

    /**
     * Builds the full user-turn prompt for this task.
     * Injects outputs of any declared context tasks when available in priorTaskOutputs.
     *
     * @param priorTaskOutputs Map of task name → output string from previously completed tasks
     */
    public String buildPrompt(Map<String, String> priorTaskOutputs) {
        String prompt = '## Task: ' + name + '\n\n'
            + description + '\n\n'
            + '## Expected Output\n' + expectedOutput;

        if (!contextTaskNames.isEmpty() && priorTaskOutputs != null) {
            List<String> contextParts = new List<String>();
            for (String ctxTaskName : contextTaskNames) {
                String output = priorTaskOutputs.get(ctxTaskName);
                if (String.isNotBlank(output)) {
                    contextParts.add('### Output from "' + ctxTaskName + '":\n' + output);
                }
            }
            if (!contextParts.isEmpty()) {
                prompt += '\n\n## Context from Prior Tasks\n'
                    + 'Use the following results from previously completed tasks to inform your response:\n\n'
                    + String.join(contextParts, '\n\n');
            }
        }

        return prompt;
    }
}
