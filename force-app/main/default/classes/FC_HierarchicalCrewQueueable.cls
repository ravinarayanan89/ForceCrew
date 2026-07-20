/**
 * FC_HierarchicalCrewQueueable - Runs a ForceCrew HIERARCHICAL crew asynchronously
 * via Queueable chaining, one manager round per job.
 *
 * WHY THIS EXISTS:
 *   FC_ManagerAgent.execute() runs the manager's entire decision loop (up to 20 rounds,
 *   each round potentially running a full agent ReAct loop) inside ONE Apex transaction.
 *   Synchronous Apex has a ~10s CPU limit and a shared per-transaction callout budget,
 *   so any hierarchical crew doing real multi-step work will blow past those limits.
 *
 * HOW IT WORKS (mirrors FC_CrewQueueable's one-task-per-job design):
 *   enqueue()
 *     └─▶ creates FC_CrewRun__c record (stores crew config JSON, status=Pending)
 *         └─▶ enqueues Job[round=0]
 *
 *   Job[round].execute()
 *     1. Reads FC_CrewRun__c by Id (config + accumulated task outputs + manager history)
 *     2. Makes ONE manager LLM call
 *     3. If DELEGATE     → runs the delegated agent's full FC_AgentExecutor loop in this
 *                          same job (bounded by that agent's own maxIterations), records
 *                          the result in the manager's history, then enqueues Job[round+1]
 *     4. If FINAL_ANSWER → marks FC_CrewRun__c.Status__c = 'Completed'
 *
 *   Each job makes at most (1 manager call + 1 agent's maxIterations) LLM callouts —
 *   comfortably inside a single transaction's callout budget regardless of how many
 *   rounds or tasks the crew needs overall, since rounds run across separate jobs.
 *
 * Shares the FC_CrewRun__c object and CrewRunConfig/AgentConfig/TaskConfig DTOs with
 * FC_CrewQueueable — see FC_CrewQueueable.setupInstructions() for required fields.
 *
 * @group ForceCrew
 */
public class FC_HierarchicalCrewQueueable implements Queueable {

    private static final Integer DEFAULT_MAX_ROUNDS = 20;

    private Id      crewRunId;
    private Integer round;

    public FC_HierarchicalCrewQueueable(Id crewRunId, Integer round) {
        this.crewRunId = crewRunId;
        this.round     = round;
    }

    // ─── Public Entry Point ───────────────────────────────────────────────────

    /**
     * Converts an FC_Crew into a serialisable config, saves it to FC_CrewRun__c,
     * and enqueues round[0].
     *
     * @param crew          Fully configured HIERARCHICAL FC_Crew
     * @param inputs        Runtime key/value inputs available as initial context
     * @param correlationId Optional external Id to correlate the async result (e.g., a record Id)
     * @return The Id of the FC_CrewRun__c record (use this to poll status or link the result)
     */
    public static Id enqueue(FC_Crew crew, Map<String, Object> inputs, String correlationId) {
        if (crew.getProcess() != FC_Process.Type.HIERARCHICAL) {
            throw new FC_Exception.ConfigurationException(
                'FC_HierarchicalCrewQueueable supports HIERARCHICAL process only. '
                + 'Use FC_CrewQueueable for SEQUENTIAL crews.'
            );
        }

        FC_CrewQueueable.CrewRunConfig config     = FC_CrewQueueable.buildCrewRunConfig(crew, correlationId);
        String                         configJson = JSON.serialize(config);

        Map<String, String> taskOutputs = new Map<String, String>();
        if (inputs != null) {
            for (String k : inputs.keySet()) {
                Object v = inputs.get(k);
                taskOutputs.put(k, v != null ? String.valueOf(v) : '');
            }
        }

        SObject run = (SObject) Type.forName('FC_CrewRun__c').newInstance();
        run.put('CrewName__c',        config.crewName);
        run.put('Status__c',          FC_CrewQueueable.STATUS_PENDING);
        run.put('CrewConfigJson__c',  configJson);
        run.put('TaskOutputsJson__c', JSON.serialize(taskOutputs));
        run.put('CorrelationId__c',   correlationId);
        insert run;

        Id runId = run.Id;
        FC_Logger.info('FC_HierarchicalCrewQueueable',
            'Created FC_CrewRun__c ' + runId + ' for hierarchical crew "' + config.crewName + '"');

        System.enqueueJob(new FC_HierarchicalCrewQueueable(runId, 0));
        return runId;
    }

    /** Enqueues without inputs or correlationId. */
    public static Id enqueue(FC_Crew crew) {
        return enqueue(crew, null, null);
    }

    // ─── Queueable.execute ────────────────────────────────────────────────────

    public void execute(QueueableContext context) {
        SObject run = readCrewRunRecord(crewRunId);
        if (run == null) {
            FC_Logger.error('FC_HierarchicalCrewQueueable', 'FC_CrewRun__c not found: ' + crewRunId);
            return;
        }

        FC_CrewQueueable.CrewRunConfig config = (FC_CrewQueueable.CrewRunConfig) JSON.deserialize(
            (String) run.get('CrewConfigJson__c'), FC_CrewQueueable.CrewRunConfig.class
        );
        Map<String, String> taskOutputs = FC_CrewQueueable.deserialiseTaskOutputs(
            (String) run.get('TaskOutputsJson__c')
        );

        if (config.verbose) FC_Logger.enableDebug();

        FC_Logger.info('FC_HierarchicalCrewQueueable',
            'Round [' + round + '/' + DEFAULT_MAX_ROUNDS + ']'
            + ' crew="' + config.crewName + '"'
            + ' jobId=' + context.getJobId());

        if (round >= DEFAULT_MAX_ROUNDS) {
            finalise(config, taskOutputs, null,
                'Manager exceeded max rounds (' + DEFAULT_MAX_ROUNDS + ')');
            return;
        }

        List<FC_ChatMessage> managerHistory = deserialiseHistory((String) run.get('ManagerHistoryJson__c'));
        if (managerHistory.isEmpty()) {
            managerHistory.add(FC_ChatMessage.system(buildManagerSystemPrompt(config)));
            managerHistory.add(FC_ChatMessage.user(buildManagerInitialPrompt(taskOutputs)));
        }

        FC_ModelsAPIService              llmService = new FC_ModelsAPIService(config.managerLlmModel);
        FC_ModelsAPIService.ChatResponse response   = llmService.chat(managerHistory);

        if (!response.isSuccess) {
            finalise(config, taskOutputs, null, 'Manager LLM error: ' + response.errorMessage);
            return;
        }

        managerHistory.add(FC_ChatMessage.assistant(response.content));

        Map<String, Object> directive = parseDirective(response.content);

        if (directive == null) {
            managerHistory.add(FC_ChatMessage.user(
                'Error: Your response was not valid JSON. Please provide a valid JSON directive.'
            ));
            advance(config, taskOutputs, managerHistory);
            return;
        }

        String action = (String) directive.get('action');

        if (action == 'DELEGATE') {
            handleDelegate(directive, config, managerHistory, taskOutputs);
            advance(config, taskOutputs, managerHistory);

        } else if (action == 'FINAL_ANSWER') {
            String summary = (String) directive.get('summary');
            FC_Logger.info('FC_HierarchicalCrewQueueable',
                'Manager concluded after ' + (round + 1) + ' round(s).');
            finalise(config, taskOutputs,
                String.isNotBlank(summary) ? summary : lastTaskOutput(config, taskOutputs), null);

        } else {
            managerHistory.add(FC_ChatMessage.user(
                'Error: Unknown action "' + action + '". Use "DELEGATE" or "FINAL_ANSWER".'
            ));
            advance(config, taskOutputs, managerHistory);
        }
    }

    // ─── Delegate Handler ────────────────────────────────────────────────────

    private void handleDelegate(
        Map<String, Object>            directive,
        FC_CrewQueueable.CrewRunConfig config,
        List<FC_ChatMessage>           managerHistory,
        Map<String, String>            taskOutputs
    ) {
        String taskName    = (String) directive.get('task');
        String agentRole   = (String) directive.get('agent');
        String instruction = (String) directive.get('instruction');

        FC_CrewQueueable.TaskConfig  taskCfg  = getTaskByName(config, taskName);
        FC_CrewQueueable.AgentConfig agentCfg = getAgentByRole(config, agentRole);

        if (taskCfg == null) {
            managerHistory.add(FC_ChatMessage.user(
                'Error: Task "' + taskName + '" not found. Available tasks: ' + getTaskNames(config)
            ));
            return;
        }
        if (agentCfg == null) {
            managerHistory.add(FC_ChatMessage.user(
                'Error: Agent "' + agentRole + '" not found. Available agents: ' + getAgentRoles(config)
            ));
            return;
        }

        FC_Agent agent;
        try {
            agent = FC_CrewQueueable.buildAgent(agentCfg);
        } catch (Exception e) {
            FC_Logger.warn('FC_HierarchicalCrewQueueable',
                'Could not build agent "' + agentRole + '": ' + e.getMessage());
            managerHistory.add(FC_ChatMessage.user(
                'Task "' + taskName + '" FAILED — agent "' + agentRole + '" could not be built: '
                + e.getMessage() + '\nYou may re-delegate to a different agent.'
            ));
            return;
        }

        FC_Logger.info('FC_HierarchicalCrewQueueable',
            'Delegating "' + taskName + '" to agent "' + agentRole + '"');

        FC_Task task = FC_CrewQueueable.buildTask(taskCfg);
        if (String.isNotBlank(instruction)) {
            task = new FC_Task.Builder(task.name)
                .description(instruction)
                .expectedOutput(task.expectedOutput)
                .assignToAgent(task.assignedAgentRole)
                .withContextFrom(task.contextTaskNames)
                .build();
        }

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult     result  = executor.execute(task, taskOutputs);

        if (result.success) {
            taskOutputs.put(taskName, result.output);
            managerHistory.add(FC_ChatMessage.user(
                'Task "' + taskName + '" completed by "' + agentRole + '".\n\nResult:\n' + result.output
            ));
        } else {
            managerHistory.add(FC_ChatMessage.user(
                'Task "' + taskName + '" FAILED when executed by "' + agentRole + '".\n'
                + 'Error: ' + result.errorMessage + '\n'
                + 'You may re-delegate to a different agent or adjust the instruction.'
            ));
        }
    }

    // ─── Advance / Finalise ───────────────────────────────────────────────────

    private void advance(
        FC_CrewQueueable.CrewRunConfig config,
        Map<String, String>            taskOutputs,
        List<FC_ChatMessage>           managerHistory
    ) {
        updateCrewRunStatus(FC_CrewQueueable.STATUS_RUNNING, null, null, taskOutputs, managerHistory);
        System.enqueueJob(new FC_HierarchicalCrewQueueable(crewRunId, round + 1));
    }

    private void finalise(
        FC_CrewQueueable.CrewRunConfig config,
        Map<String, String>            taskOutputs,
        String                         finalOutput,
        String                         errorMessage
    ) {
        String status = String.isBlank(errorMessage)
            ? FC_CrewQueueable.STATUS_COMPLETED
            : FC_CrewQueueable.STATUS_FAILED;
        updateCrewRunStatus(status, finalOutput, errorMessage, taskOutputs, null);

        FC_Logger.info('FC_HierarchicalCrewQueueable',
            'Crew "' + config.crewName + '" ' + status
            + (String.isBlank(errorMessage) ? '' : ' — ' + errorMessage));
    }

    private String lastTaskOutput(FC_CrewQueueable.CrewRunConfig config, Map<String, String> taskOutputs) {
        for (Integer i = config.tasks.size() - 1; i >= 0; i--) {
            String out = taskOutputs.get(config.tasks[i].name);
            if (String.isNotBlank(out)) return out;
        }
        return null;
    }

    // ─── Record Operations ────────────────────────────────────────────────────

    private static SObject readCrewRunRecord(Id runId) {
        try {
            List<SObject> records = Database.query(
                'SELECT Id, CrewConfigJson__c, TaskOutputsJson__c, ManagerHistoryJson__c, Status__c '
                + 'FROM FC_CrewRun__c WHERE Id = :runId LIMIT 1'
            );
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            FC_Logger.error('FC_HierarchicalCrewQueueable', 'Failed to read FC_CrewRun__c: ' + e.getMessage());
            return null;
        }
    }

    private void updateCrewRunStatus(
        String                status,
        String                finalOutput,
        String                errorMessage,
        Map<String, String>   taskOutputs,
        List<FC_ChatMessage>  managerHistory
    ) {
        try {
            SObject run = (SObject) Type.forName('FC_CrewRun__c').newInstance();
            run.put('Id',                  crewRunId);
            run.put('Status__c',           status);
            run.put('TaskOutputsJson__c',  JSON.serialize(taskOutputs));
            if (managerHistory != null) run.put('ManagerHistoryJson__c', serialiseHistory(managerHistory));
            if (finalOutput  != null)   run.put('FinalOutput__c',  finalOutput);
            if (errorMessage != null)   run.put('ErrorMessage__c', errorMessage);
            update run;
        } catch (Exception e) {
            FC_Logger.error('FC_HierarchicalCrewQueueable', 'Failed to update FC_CrewRun__c: ' + e.getMessage());
        }
    }

    // ─── History (De)serialisation ────────────────────────────────────────────

    @TestVisible
    private static List<FC_ChatMessage> deserialiseHistory(String json_x) {
        if (String.isBlank(json_x)) return new List<FC_ChatMessage>();
        List<Object>          raw      = (List<Object>) JSON.deserializeUntyped(json_x);
        List<FC_ChatMessage>  messages = new List<FC_ChatMessage>();
        for (Object item : raw) {
            Map<String, Object> msg = (Map<String, Object>) item;
            messages.add(new FC_ChatMessage((String) msg.get('role'), (String) msg.get('content')));
        }
        return messages;
    }

    private static String serialiseHistory(List<FC_ChatMessage> messages) {
        List<Map<String, Object>> raw = new List<Map<String, Object>>();
        for (FC_ChatMessage msg : messages) {
            raw.add(new Map<String, Object>{ 'role' => msg.role, 'content' => msg.content });
        }
        return JSON.serialize(raw);
    }

    // ─── Directive Parsing ────────────────────────────────────────────────────

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

    // ─── Prompts ──────────────────────────────────────────────────────────────

    private String buildManagerSystemPrompt(FC_CrewQueueable.CrewRunConfig config) {
        List<String> agentDescriptions = new List<String>();
        for (FC_CrewQueueable.AgentConfig a : config.agents) {
            Boolean hasTools = a.toolClassNames != null && !a.toolClassNames.isEmpty();
            agentDescriptions.add(
                '- "' + a.role + '": ' + a.goal
                + (hasTools ? ' [Tools: ' + String.join(a.toolClassNames, ', ') + ']' : ' [No tools]')
            );
        }

        List<String> taskDescriptions = new List<String>();
        for (FC_CrewQueueable.TaskConfig t : config.tasks) {
            taskDescriptions.add(
                '- "' + t.name + '": ' + t.description
                + '\n  Expected: ' + t.expectedOutput
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

    private String buildManagerInitialPrompt(Map<String, String> taskOutputs) {
        String inputContext = (taskOutputs != null && !taskOutputs.isEmpty())
            ? '\n\nInputs provided:\n' + JSON.serializePretty(taskOutputs)
            : '';
        return 'Please coordinate the crew to complete all assigned tasks.'
            + inputContext
            + '\nStart by delegating the first appropriate task.';
    }

    // ─── Config Lookups ───────────────────────────────────────────────────────

    private FC_CrewQueueable.TaskConfig getTaskByName(FC_CrewQueueable.CrewRunConfig config, String name) {
        for (FC_CrewQueueable.TaskConfig t : config.tasks) {
            if (t.name == name) return t;
        }
        return null;
    }

    private FC_CrewQueueable.AgentConfig getAgentByRole(FC_CrewQueueable.CrewRunConfig config, String role) {
        for (FC_CrewQueueable.AgentConfig a : config.agents) {
            if (a.role == role) return a;
        }
        return null;
    }

    private String getTaskNames(FC_CrewQueueable.CrewRunConfig config) {
        List<String> names = new List<String>();
        for (FC_CrewQueueable.TaskConfig t : config.tasks) names.add('"' + t.name + '"');
        return String.join(names, ', ');
    }

    private String getAgentRoles(FC_CrewQueueable.CrewRunConfig config) {
        List<String> roles = new List<String>();
        for (FC_CrewQueueable.AgentConfig a : config.agents) roles.add('"' + a.role + '"');
        return String.join(roles, ', ');
    }
}
