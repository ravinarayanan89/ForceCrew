/**
 * FC_ManagerAgent - The manager LLM for hierarchical crew execution.
 *
 * In a HIERARCHICAL crew, the manager agent acts as an AI orchestrator:
 * it reviews all available agents and tasks, then dynamically delegates work
 * to the most appropriate agent, adapting based on intermediate results.
 *
 * The manager communicates via the same ReAct-style JSON protocol, but with
 * DELEGATE and FINAL_ANSWER actions instead of TOOL_CALL.
 *
 * @group ForceCrew
 */
public with sharing class FC_ManagerAgent {

    private static final Integer DEFAULT_MAX_ROUNDS = 20;

    private FC_Crew             crew;
    private FC_ModelsAPIService llmService;

    public FC_ManagerAgent(FC_Crew crew) {
        this.crew       = crew;
        this.llmService = new FC_ModelsAPIService(crew.getManagerLlmModel());
    }

    // ─── Execution ────────────────────────────────────────────────────────────

    public void execute(FC_CrewResult crewResult, Map<String, Object> inputs) {
        List<FC_ChatMessage> managerHistory = new List<FC_ChatMessage>();
        Map<String, String>  taskOutputs   = new Map<String, String>();

        // Seed context map from inputs
        if (inputs != null) {
            for (String key : inputs.keySet()) {
                Object val = inputs.get(key);
                taskOutputs.put(key, val != null ? String.valueOf(val) : '');
            }
        }

        managerHistory.add(FC_ChatMessage.system(buildManagerSystemPrompt()));
        managerHistory.add(FC_ChatMessage.user(buildManagerInitialPrompt(inputs)));

        for (Integer round = 0; round < DEFAULT_MAX_ROUNDS; round++) {
            FC_Logger.info('FC_ManagerAgent', 'Manager round ' + (round + 1));

            FC_ModelsAPIService.ChatResponse response = llmService.chat(managerHistory);
            if (!response.isSuccess) {
                throw new FC_Exception.LLMException('Manager LLM error: ' + response.errorMessage);
            }

            managerHistory.add(FC_ChatMessage.assistant(response.content));

            Map<String, Object> directive = parseDirective(response.content);
            if (directive == null) {
                managerHistory.add(FC_ChatMessage.user(
                    'Error: Your response was not valid JSON. Please provide a valid JSON directive.'
                ));
                continue;
            }

            String action = (String) directive.get('action');

            if (action == 'DELEGATE') {
                handleDelegate(directive, crewResult, managerHistory, taskOutputs);

            } else if (action == 'FINAL_ANSWER') {
                FC_Logger.info('FC_ManagerAgent', 'Manager concluded after ' + (round + 1) + ' round(s).');
                return;

            } else {
                managerHistory.add(FC_ChatMessage.user(
                    'Error: Unknown action "' + action + '". Use "DELEGATE" or "FINAL_ANSWER".'
                ));
            }
        }

        throw new FC_Exception.MaxIterationsException(
            'Manager agent exceeded max rounds (' + DEFAULT_MAX_ROUNDS + ')'
        );
    }

    // ─── Delegate Handler ────────────────────────────────────────────────────

    private void handleDelegate(
        Map<String, Object> directive,
        FC_CrewResult       crewResult,
        List<FC_ChatMessage> managerHistory,
        Map<String, String> taskOutputs
    ) {
        String taskName    = (String) directive.get('task');
        String agentRole   = (String) directive.get('agent');
        String instruction = (String) directive.get('instruction');

        FC_Task  task  = getTaskByName(taskName);
        FC_Agent agent = crew.getAgent(agentRole);

        if (task == null) {
            managerHistory.add(FC_ChatMessage.user(
                'Error: Task "' + taskName + '" not found. Available tasks: ' + getTaskNames()
            ));
            return;
        }
        if (agent == null) {
            managerHistory.add(FC_ChatMessage.user(
                'Error: Agent "' + agentRole + '" not found. Available agents: ' + getAgentRoles()
            ));
            return;
        }

        FC_Logger.info('FC_ManagerAgent',
            'Delegating "' + taskName + '" to agent "' + agentRole + '"');

        // Optionally override the task description with manager's specific instruction
        FC_Task delegatedTask = String.isNotBlank(instruction)
            ? buildOverrideTask(task, instruction)
            : task;

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult    taskResult = executor.execute(delegatedTask, taskOutputs);
        crewResult.addTaskResult(taskResult);

        if (taskResult.success) {
            taskOutputs.put(taskName, taskResult.output);
            managerHistory.add(FC_ChatMessage.user(
                'Task "' + taskName + '" completed by "' + agentRole + '".\n\nResult:\n' + taskResult.output
            ));
        } else {
            managerHistory.add(FC_ChatMessage.user(
                'Task "' + taskName + '" FAILED when executed by "' + agentRole + '".\n'
                + 'Error: ' + taskResult.errorMessage + '\n'
                + 'You may re-delegate to a different agent or adjust the instruction.'
            ));
        }
    }

    // ─── Prompts ──────────────────────────────────────────────────────────────

    private String buildManagerSystemPrompt() {
        List<String> agentDescriptions = new List<String>();
        for (FC_Agent agent : crew.getAgents()) {
            agentDescriptions.add(
                '- "' + agent.role + '": ' + agent.goal
                + (agent.hasTools()
                    ? ' [Tools: ' + getToolNames(agent) + ']'
                    : ' [No tools]')
            );
        }

        List<String> taskDescriptions = new List<String>();
        for (FC_Task task : crew.getTasks()) {
            taskDescriptions.add(
                '- "' + task.name + '": ' + task.description
                + '\n  Expected: ' + task.expectedOutput
            );
        }

        return 'You are the manager of an AI crew. '
            + 'Your job is to coordinate agents to complete all tasks efficiently.\n\n'
            + '## Available Agents\n' + String.join(agentDescriptions, '\n') + '\n\n'
            + '## Tasks to Complete\n' + String.join(taskDescriptions, '\n') + '\n\n'
            + '## Your Response Format\n'
            + 'Respond with ONLY valid JSON. No markdown fences, no extra text.\n\n'
            + 'To delegate a task to an agent:\n'
            + '{"action":"DELEGATE","task":"<exact task name>","agent":"<exact agent role>",'
            + '"instruction":"<optional: override description for this agent>"}\n\n'
            + 'When all required tasks are done:\n'
            + '{"action":"FINAL_ANSWER","summary":"<brief summary of what was accomplished>"}';
    }

    private String buildManagerInitialPrompt(Map<String, Object> inputs) {
        String inputContext = (inputs != null && !inputs.isEmpty())
            ? '\n\nInputs provided:\n' + JSON.serializePretty(inputs)
            : '';
        return 'Please coordinate the crew to complete all assigned tasks.'
            + inputContext
            + '\nStart by delegating the first appropriate task.';
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private Map<String, Object> parseDirective(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            String cleaned = raw.trim();
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

    private FC_Task getTaskByName(String taskName) {
        for (FC_Task task : crew.getTasks()) {
            if (task.name == taskName) return task;
        }
        return null;
    }

    private String getTaskNames() {
        List<String> names = new List<String>();
        for (FC_Task task : crew.getTasks()) names.add('"' + task.name + '"');
        return String.join(names, ', ');
    }

    private String getAgentRoles() {
        List<String> roles = new List<String>();
        for (FC_Agent agent : crew.getAgents()) roles.add('"' + agent.role + '"');
        return String.join(roles, ', ');
    }

    private String getToolNames(FC_Agent agent) {
        List<String> names = new List<String>();
        for (FC_Tool t : agent.tools) names.add(t.getName());
        return String.join(names, ', ');
    }

    private FC_Task buildOverrideTask(FC_Task original, String newDescription) {
        return new FC_Task.Builder(original.name)
            .description(newDescription)
            .expectedOutput(original.expectedOutput)
            .assignToAgent(original.assignedAgentRole)
            .withContextFrom(original.contextTaskNames)
            .build();
    }
}
