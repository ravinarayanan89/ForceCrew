/**
 * FC_AgentExecutor - Runs a single agent on a single task using the ReAct (Reason + Act) pattern.
 *
 * Execution loop:
 *   1. Initialise memory with the agent's system prompt
 *   2. Send the task prompt as the first user message
 *   3. Call the LLM and parse the JSON response
 *   4. If TOOL_CALL  → execute the tool, add tool result as user message, repeat
 *   5. If FINAL_ANSWER → return the answer, done
 *   6. If max iterations reached → throw MaxIterationsException
 *
 * The executor is single-use per task. Create a new instance for each task execution,
 * or call resetMemory() between reuses.
 *
 * @group ForceCrew
 */
public with sharing class FC_AgentExecutor {

    private FC_Agent             agent;
    private FC_ModelsAPIService  llmService;
    private FC_Memory            memory;

    public FC_AgentExecutor(FC_Agent agent) {
        this.agent      = agent;
        this.llmService = new FC_ModelsAPIService(agent.llmModel);
        this.memory     = new FC_Memory();
    }

    // ─── Execution ────────────────────────────────────────────────────────────

    /**
     * Executes the given task and returns a detailed FC_TaskResult.
     *
     * @param task             The task to execute
     * @param priorTaskOutputs Map of task name → output for context injection (may be null)
     */
    public FC_TaskResult execute(FC_Task task, Map<String, String> priorTaskOutputs) {
        FC_TaskResult result   = new FC_TaskResult(task.name, task.description, agent.role);
        Long          startMs  = DateTime.now().getTime();

        FC_Logger.info('FC_AgentExecutor',
            'Agent "' + agent.role + '" starting task "' + task.name + '"');

        try {
            // ── Initialise memory ─────────────────────────────────────────────
            memory.clear();
            memory.add(FC_ChatMessage.system(agent.buildSystemPrompt()));
            memory.add(FC_ChatMessage.user(
                task.buildPrompt(priorTaskOutputs != null ? priorTaskOutputs : new Map<String, String>())
            ));

            // ── ReAct loop ────────────────────────────────────────────────────
            for (Integer iteration = 0; iteration < agent.maxIterations; iteration++) {
                FC_Logger.debug('FC_AgentExecutor',
                    'Iteration ' + (iteration + 1) + '/' + agent.maxIterations
                    + ' | Agent: ' + agent.role + ' | Task: ' + task.name);

                // Call LLM
                FC_ModelsAPIService.ChatResponse llmResponse = llmService.chat(memory.getHistory());

                if (!llmResponse.isSuccess) {
                    throw new FC_Exception.LLMException(llmResponse.errorMessage);
                }

                String rawResponse = llmResponse.content;

                if (agent.verbose) {
                    FC_Logger.debug('FC_AgentExecutor', 'Raw LLM response: ' + rawResponse);
                }

                // Parse JSON
                Map<String, Object> parsed = parseJsonResponse(rawResponse);

                if (parsed == null) {
                    FC_StepResult errStep = FC_StepResult.error(
                        'LLM response is not valid JSON', rawResponse
                    );
                    result.addStep(errStep);
                    memory.add(FC_ChatMessage.assistant(rawResponse));
                    memory.add(FC_ChatMessage.user(
                        'Error: Your last response was not valid JSON. '
                        + 'Please respond with only a valid JSON object matching the required format.'
                    ));
                    continue;
                }

                String action = (String) parsed.get('action');
                String thought = (String) parsed.get('thought');

                // Add assistant turn to memory
                memory.add(FC_ChatMessage.assistant(rawResponse));

                // ── Dispatch ──────────────────────────────────────────────────

                if (action == 'FINAL_ANSWER') {
                    Object answerRaw = parsed.get('answer');
                    String answer = answerRaw instanceof String
                        ? (String) answerRaw
                        : (answerRaw != null ? JSON.serialize(answerRaw) : null);
                    if (String.isBlank(answer)) {
                        memory.add(FC_ChatMessage.user(
                            'Error: FINAL_ANSWER must include a non-empty "answer" field.'
                        ));
                        continue;
                    }
                    result.addStep(FC_StepResult.finalAnswer(thought, answer));
                    result.complete(answer, DateTime.now().getTime() - startMs);
                    FC_Logger.info('FC_AgentExecutor',
                        'Task "' + task.name + '" completed after ' + (iteration + 1) + ' iteration(s)');
                    return result;

                } else if (action == 'TOOL_CALL') {
                    String             toolName   = (String)             parsed.get('tool');
                    Map<String, Object> toolParams = (Map<String, Object>) parsed.get('parameters');

                    if (String.isBlank(toolName)) {
                        memory.add(FC_ChatMessage.user(
                            'Error: TOOL_CALL must include a non-empty "tool" field.'
                        ));
                        continue;
                    }

                    FC_Logger.info('FC_AgentExecutor',
                        'Agent "' + agent.role + '" calling tool "' + toolName + '"');

                    String toolResult = executeTool(toolName, toolParams);

                    result.addStep(FC_StepResult.toolCall(thought, toolName, toolParams, toolResult));
                    memory.add(FC_ChatMessage.user(
                        'TOOL_RESULT for "' + toolName + '":\n' + toolResult
                    ));

                } else {
                    memory.add(FC_ChatMessage.user(
                        'Error: Unknown action "' + action + '". '
                        + 'Valid actions are "TOOL_CALL" and "FINAL_ANSWER".'
                    ));
                }
            }

            // Max iterations reached
            throw new FC_Exception.MaxIterationsException(
                'Agent "' + agent.role + '" exceeded max iterations (' + agent.maxIterations + ')'
                + ' on task "' + task.name + '" without a FINAL_ANSWER.'
            );

        } catch (Exception e) {
            FC_Logger.error('FC_AgentExecutor', 'Task "' + task.name + '" failed: ' + e.getMessage());
            result.fail(e.getMessage(), DateTime.now().getTime() - startMs);
        }

        return result;
    }

    // ─── Memory ───────────────────────────────────────────────────────────────

    /** Resets the agent's conversational memory. Call between task reuses. */
    public void resetMemory() {
        memory.clear();
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private String executeTool(String toolName, Map<String, Object> params) {
        FC_Tool tool = agent.getTool(toolName);
        if (tool == null) {
            String availableTools = getAvailableToolNames();
            FC_Logger.warn('FC_AgentExecutor',
                'Tool "' + toolName + '" not found. Available: ' + availableTools);
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error'   => 'Tool "' + toolName + '" not found. Available tools: ' + availableTools
            });
        }
        return tool.execute(params);
    }

    private String getAvailableToolNames() {
        List<String> names = new List<String>();
        for (FC_Tool tool : agent.tools) {
            names.add(tool.getName());
        }
        return String.join(names, ', ');
    }

    /**
     * Parses the LLM's raw string response into a Map.
     * Strips markdown code fences (```json ... ```) if present before parsing.
     */
    private Map<String, Object> parseJsonResponse(String rawResponse) {
        if (String.isBlank(rawResponse)) return null;

        try {
            String cleaned = rawResponse.trim();

            // Strip markdown code fences: ```json\n...\n``` or ```\n...\n```
            if (cleaned.startsWith('```')) {
                Integer firstNewline = cleaned.indexOf('\n');
                Integer lastFence    = cleaned.lastIndexOf('```');
                if (firstNewline > 0 && lastFence > firstNewline) {
                    cleaned = cleaned.substring(firstNewline + 1, lastFence).trim();
                }
            }

            Object parsed = JSON.deserializeUntyped(cleaned);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
            return null;
        } catch (Exception e) {
            FC_Logger.warn('FC_AgentExecutor', 'JSON parse failed: ' + e.getMessage());
            return null;
        }
    }
}
