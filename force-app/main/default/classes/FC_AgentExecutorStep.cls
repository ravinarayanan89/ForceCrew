/**
 * FC_AgentExecutorStep - Single-step (one transaction) agent execution for LWC-driven loops.
 *
 * WHEN TO USE THIS vs FC_AgentExecutor:
 *
 *   FC_AgentExecutor.execute()    → runs the FULL ReAct loop in ONE transaction.
 *                                   Simple. Use for short tasks (≤3 LLM calls expected).
 *                                   Will hit governor limits for complex, multi-step tasks.
 *
 *   FC_AgentExecutorStep.step()   → runs ONE ReAct iteration per Apex transaction.
 *                                   The LWC (or Queueable) drives the loop.
 *                                   Safe for complex tasks — no per-transaction LLM limit risk.
 *
 * LWC USAGE PATTERN:
 *
 *   // Step 1 — initialise (no LLM call yet, builds system prompt + task prompt)
 *   let state = await initStep({ agentConfigJson, taskConfigJson, inputsJson });
 *
 *   // Step 2..N — iterate until complete
 *   while (!state.isComplete) {
 *       state = await runStep({ stepRequestJson: JSON.stringify(state) });
 *   }
 *
 *   console.log(state.finalAnswer);
 *
 * HOW STATE IS PASSED:
 *   FC_StepRequest is fully serialisable. The LWC receives it as JSON after each call
 *   and passes the same JSON back in the next call. No server-side session needed.
 *
 * @group ForceCrew
 */
public with sharing class FC_AgentExecutorStep {

    private FC_Agent            agent;
    private FC_ModelsAPIService llmService;

    public FC_AgentExecutorStep(FC_Agent agent) {
        this.agent      = agent;
        this.llmService = new FC_ModelsAPIService(agent.llmModel);
    }

    // ─── Initialise ───────────────────────────────────────────────────────────

    /**
     * Builds the initial FC_StepRequest without making any LLM call.
     * Sets up the system prompt + task prompt in the conversation history.
     * Call this once before the first runStep() call.
     *
     * @param task             The task the agent will execute
     * @param priorTaskOutputs Context from previous tasks (may be null)
     */
    public FC_StepRequest initialise(FC_Task task, Map<String, String> priorTaskOutputs) {
        FC_StepRequest request    = new FC_StepRequest();
        request.agentRole         = agent.role;
        request.taskName          = task.name;
        request.maxIterations     = agent.maxIterations;
        request.iterationCount    = 0;
        request.isComplete        = false;

        List<FC_ChatMessage> history = new List<FC_ChatMessage>{
            FC_ChatMessage.system(agent.buildSystemPrompt()),
            FC_ChatMessage.user(
                task.buildPrompt(priorTaskOutputs != null ? priorTaskOutputs : new Map<String, String>())
            )
        };
        request.setHistory(history);

        FC_Logger.info('FC_AgentExecutorStep',
            'Initialised step execution for task "' + task.name
            + '" agent "' + agent.role + '"');

        return request;
    }

    // ─── Single Step ──────────────────────────────────────────────────────────

    /**
     * Executes ONE ReAct iteration: one LLM call + (optionally) one tool call.
     * Returns the updated FC_StepRequest for the LWC to persist and pass back next time.
     *
     * Returns request with isComplete=true when FINAL_ANSWER is reached.
     * Returns request with errorMessage set if an unrecoverable error occurs.
     *
     * Consumes: 1 Models API call per invocation (safe within per-transaction limits).
     */
    public FC_StepRequest step(FC_StepRequest request) {
        if (request == null) {
            request              = new FC_StepRequest();
            request.errorMessage = 'FC_StepRequest cannot be null';
            return request;
        }

        if (request.isComplete) {
            return request;  // Already done — caller should stop
        }

        if (request.iterationCount >= request.maxIterations) {
            request.errorMessage = 'Max iterations (' + request.maxIterations + ') reached for agent "'
                + request.agentRole + '" on task "' + request.taskName + '"';
            return request;
        }

        List<FC_ChatMessage> history = request.getHistory();
        request.iterationCount++;

        FC_Logger.info('FC_AgentExecutorStep',
            'Step ' + request.iterationCount + '/' + request.maxIterations
            + ' | Agent: ' + request.agentRole + ' | Task: ' + request.taskName);

        try {
            // ── One LLM call ──────────────────────────────────────────────────
            FC_ModelsAPIService.ChatResponse llmResponse = llmService.chat(history);

            if (!llmResponse.isSuccess) {
                request.errorMessage = 'LLM error: ' + llmResponse.errorMessage;
                return request;
            }

            String rawResponse = llmResponse.content;

            if (agent.verbose) {
                FC_Logger.debug('FC_AgentExecutorStep', 'LLM response: ' + rawResponse);
            }

            // ── Parse JSON ────────────────────────────────────────────────────
            Map<String, Object> parsed = parseJsonResponse(rawResponse);

            if (parsed == null) {
                history.add(FC_ChatMessage.assistant(rawResponse));
                history.add(FC_ChatMessage.user(
                    'Error: Your response was not valid JSON. '
                    + 'Please respond with only a valid JSON object matching the required format.'
                ));
                request.setHistory(history);
                request.lastStepJson = JSON.serialize(
                    FC_StepResult.error('Invalid JSON response', rawResponse)
                );
                return request;
            }

            String action = (String) parsed.get('action');
            String thought = (String) parsed.get('thought');

            history.add(FC_ChatMessage.assistant(rawResponse));

            // ── Dispatch ──────────────────────────────────────────────────────
            if (action == 'FINAL_ANSWER') {
                String answer = (String) parsed.get('answer');
                if (String.isBlank(answer)) {
                    history.add(FC_ChatMessage.user(
                        'Error: FINAL_ANSWER must include a non-empty "answer" field.'
                    ));
                    request.setHistory(history);
                    return request;
                }
                request.isComplete    = true;
                request.finalAnswer   = answer;
                request.lastStepJson  = JSON.serialize(FC_StepResult.finalAnswer(thought, answer));
                request.setHistory(history);

                FC_Logger.info('FC_AgentExecutorStep',
                    'FINAL_ANSWER reached after ' + request.iterationCount + ' step(s)');

            } else if (action == 'TOOL_CALL') {
                String              toolName   = (String)             parsed.get('tool');
                Map<String, Object> toolParams = (Map<String, Object>) parsed.get('parameters');

                if (String.isBlank(toolName)) {
                    history.add(FC_ChatMessage.user(
                        'Error: TOOL_CALL must include a non-empty "tool" field.'
                    ));
                    request.setHistory(history);
                    return request;
                }

                FC_Logger.info('FC_AgentExecutorStep',
                    'Tool call: "' + toolName + '"');

                String toolResult = executeTool(toolName, toolParams);

                history.add(FC_ChatMessage.user(
                    'Tool "' + toolName + '" returned:\n' + toolResult
                ));
                request.setHistory(history);
                request.lastStepJson = JSON.serialize(
                    FC_StepResult.toolCall(thought, toolName, toolParams, toolResult)
                );

            } else {
                history.add(FC_ChatMessage.user(
                    'Error: Unknown action "' + action + '". '
                    + 'Valid actions are "TOOL_CALL" and "FINAL_ANSWER".'
                ));
                request.setHistory(history);
            }

        } catch (Exception e) {
            FC_Logger.error('FC_AgentExecutorStep', 'Step error: ' + e.getMessage());
            request.errorMessage = e.getMessage();
        }

        return request;
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private String executeTool(String toolName, Map<String, Object> params) {
        FC_Tool tool = agent.getTool(toolName);
        if (tool == null) {
            List<String> names = new List<String>();
            for (FC_Tool t : agent.tools) names.add(t.getName());
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error'   => 'Tool "' + toolName + '" not found. Available: '
                             + String.join(names, ', ')
            });
        }
        return tool.execute(params);
    }

    private Map<String, Object> parseJsonResponse(String rawResponse) {
        if (String.isBlank(rawResponse)) return null;
        try {
            String cleaned = rawResponse.trim();
            if (cleaned.startsWith('```')) {
                Integer firstNewline = cleaned.indexOf('\n');
                Integer lastFence    = cleaned.lastIndexOf('```');
                if (firstNewline > 0 && lastFence > firstNewline) {
                    cleaned = cleaned.substring(firstNewline + 1, lastFence).trim();
                }
            }
            Object parsed = JSON.deserializeUntyped(cleaned);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (Exception e) {
            return null;
        }
    }
}
