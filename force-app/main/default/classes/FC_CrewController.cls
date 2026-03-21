/**
 * FC_CrewController - AuraEnabled controller for LWC integration with ForceCrew.
 *
 * Exposes crew execution to Lightning Web Components via @AuraEnabled methods.
 * All methods are cacheable=false because they invoke the LLM (non-deterministic, non-cacheable).
 *
 * Typical LWC usage:
 *   const result = await runCrew({ crewConfigJson: JSON.stringify(crewConfig) });
 *
 * @group ForceCrew
 */
public with sharing class FC_CrewController {

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    /**
     * Wire-safe result DTO returned to LWC.
     * Uses plain types only (String, Boolean, List, Map) for AuraEnabled transport.
     */
    public class CrewResultDTO {
        @AuraEnabled public Boolean             success         { get; set; }
        @AuraEnabled public String              crewName        { get; set; }
        @AuraEnabled public String              finalOutput     { get; set; }
        @AuraEnabled public String              errorMessage    { get; set; }
        @AuraEnabled public Long                executionTimeMs { get; set; }
        @AuraEnabled public Integer             taskCount       { get; set; }
        @AuraEnabled public Integer             successfulTasks { get; set; }
        @AuraEnabled public Integer             totalToolCalls  { get; set; }
        @AuraEnabled public List<TaskResultDTO> tasks           { get; set; }
        @AuraEnabled public List<String>        logs            { get; set; }
    }

    public class TaskResultDTO {
        @AuraEnabled public String             taskName        { get; set; }
        @AuraEnabled public String             agentRole       { get; set; }
        @AuraEnabled public String             output          { get; set; }
        @AuraEnabled public Boolean            success         { get; set; }
        @AuraEnabled public String             errorMessage    { get; set; }
        @AuraEnabled public Long               executionTimeMs { get; set; }
        @AuraEnabled public Integer            toolCallCount   { get; set; }
        @AuraEnabled public List<StepResultDTO> steps          { get; set; }
    }

    public class StepResultDTO {
        @AuraEnabled public String  stepType   { get; set; }
        @AuraEnabled public String  thought    { get; set; }
        @AuraEnabled public String  toolName   { get; set; }
        @AuraEnabled public String  toolResult { get; set; }
        @AuraEnabled public String  answer     { get; set; }
        @AuraEnabled public Boolean success    { get; set; }
        @AuraEnabled public String  error      { get; set; }
    }

    // ─── AuraEnabled Methods ──────────────────────────────────────────────────

    /**
     * Executes a crew defined by JSON configuration.
     * The crewConfigJson must be a serialised Map<String,Object> matching the expected schema.
     *
     * This method is intentionally generic to support dynamic crew assembly from LWC/Flow.
     * For type-safe Apex-only usage, construct FC_Crew directly and call kickoff().
     *
     * Expected crewConfigJson schema:
     * {
     *   "crewName":  "My Crew",
     *   "process":   "SEQUENTIAL" | "HIERARCHICAL",
     *   "verbose":   true | false,
     *   "agents": [{
     *     "role":       "Analyst",
     *     "goal":       "...",
     *     "backstory":  "...",
     *     "toolClasses": ["FC_SampleSOQLTool", "FC_SampleDescribeTool"]
     *   }],
     *   "tasks": [{
     *     "name":           "Task 1",
     *     "description":    "...",
     *     "expectedOutput": "...",
     *     "assignToAgent":  "Analyst",
     *     "contextTasks":   ["Other Task"]
     *   }],
     *   "inputs": { "key": "value" }
     * }
     */
    @AuraEnabled(cacheable=false)
    public static CrewResultDTO runCrewFromConfig(String crewConfigJson) {
        FC_Logger.clearBuffer();
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(crewConfigJson);
            FC_Crew crew = buildCrewFromConfig(config);

            Map<String, Object> inputs = config.containsKey('inputs')
                ? (Map<String, Object>) config.get('inputs')
                : null;

            FC_CrewResult result = crew.kickoff(inputs);
            return toDTO(result);

        } catch (Exception e) {
            FC_Logger.error('FC_CrewController', 'runCrewFromConfig error: ' + e.getMessage());
            CrewResultDTO errorDTO    = new CrewResultDTO();
            errorDTO.success          = false;
            errorDTO.errorMessage     = e.getMessage();
            errorDTO.logs             = collectLogs();
            return errorDTO;
        }
    }

    /**
     * Simple single-agent invocation from LWC.
     * No crew setup required — great for quick AI calls from components.
     *
     * @param agentRole  Role label for the agent
     * @param goal       Agent's goal
     * @param backstory  Agent's backstory
     * @param toolClasses List of FC_IMCPTool class names to register (e.g., ['FC_SampleSOQLTool'])
     * @param taskDescription  What the agent should do
     * @param expectedOutput   Expected output format
     */
    @AuraEnabled(cacheable=false)
    public static CrewResultDTO runSingleAgent(
        String       agentRole,
        String       goal,
        String       backstory,
        List<String> toolClasses,
        String       taskDescription,
        String       expectedOutput
    ) {
        FC_Logger.clearBuffer();
        try {
            FC_Agent.Builder agentBuilder = new FC_Agent.Builder(agentRole)
                .goal(goal)
                .backstory(backstory);

            if (toolClasses != null) {
                for (String cls : toolClasses) {
                    if (String.isNotBlank(cls)) {
                        agentBuilder.tool(FC_Tool.fromClassName(cls));
                    }
                }
            }

            FC_Task task = new FC_Task.Builder('Task')
                .description(taskDescription)
                .expectedOutput(expectedOutput)
                .assignToAgent(agentRole)
                .build();

            FC_CrewResult result = new FC_Crew.Builder('Single-Agent Crew')
                .agent(agentBuilder.build())
                .task(task)
                .build()
                .kickoff();

            return toDTO(result);

        } catch (Exception e) {
            FC_Logger.error('FC_CrewController', 'runSingleAgent error: ' + e.getMessage());
            CrewResultDTO errorDTO = new CrewResultDTO();
            errorDTO.success       = false;
            errorDTO.errorMessage  = e.getMessage();
            errorDTO.logs          = collectLogs();
            return errorDTO;
        }
    }

    /**
     * Returns the framework version and basic health info.
     */
    @AuraEnabled(cacheable=true)
    public static String getFrameworkInfo() {
        return ForceCrew.about();
    }

    // ─── Step-by-Step Execution (Governor-Limit Safe) ─────────────────────────
    //
    // These methods allow LWC to drive the ReAct loop one step at a time.
    // Each call = one Apex transaction = one LLM call.
    // The LWC holds the FC_StepRequest JSON between calls.
    //
    // Pattern:
    //   1. Call initAgentStep() once to get the initial state
    //   2. Call runAgentStep() in a loop until state.isComplete === true
    //   3. Read state.finalAnswer for the result
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Initialises a step-by-step agent execution. Returns initial FC_StepRequest state.
     * Does NOT call the LLM — just sets up the conversation history.
     *
     * @param agentConfigJson  JSON of a single agent config (same schema as agents[] in runCrewFromConfig)
     * @param taskConfigJson   JSON of a single task config (same schema as tasks[] in runCrewFromConfig)
     * @param priorOutputsJson JSON map of prior task name → output for context injection (nullable)
     */
    @AuraEnabled(cacheable=false)
    public static FC_StepRequest initAgentStep(
        String agentConfigJson,
        String taskConfigJson,
        String priorOutputsJson
    ) {
        try {
            Map<String, Object> agentCfg = (Map<String, Object>) JSON.deserializeUntyped(agentConfigJson);
            Map<String, Object> taskCfg  = (Map<String, Object>) JSON.deserializeUntyped(taskConfigJson);

            FC_Agent agent = buildAgentFromConfig(agentCfg);
            FC_Task  task  = buildTaskFromConfig(taskCfg);

            Map<String, String> priorOutputs = new Map<String, String>();
            if (String.isNotBlank(priorOutputsJson)) {
                Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(priorOutputsJson);
                for (String k : raw.keySet()) {
                    priorOutputs.put(k, raw.get(k) != null ? String.valueOf(raw.get(k)) : '');
                }
            }

            FC_AgentExecutorStep executor = new FC_AgentExecutorStep(agent);
            return executor.initialise(task, priorOutputs);

        } catch (Exception e) {
            FC_StepRequest errReq = new FC_StepRequest();
            errReq.errorMessage  = e.getMessage();
            return errReq;
        }
    }

    /**
     * Runs ONE step of the ReAct loop. Makes exactly ONE LLM call per invocation.
     * Pass the FC_StepRequest returned by the previous call back in as stepRequestJson.
     *
     * Returns updated FC_StepRequest. Check isComplete to know when to stop.
     *
     * @param agentConfigJson  JSON of the same agent config used in initAgentStep()
     * @param stepRequestJson  JSON of the FC_StepRequest from the previous call
     */
    @AuraEnabled(cacheable=false)
    public static FC_StepRequest runAgentStep(String agentConfigJson, String stepRequestJson) {
        try {
            Map<String, Object> agentCfg = (Map<String, Object>) JSON.deserializeUntyped(agentConfigJson);
            FC_Agent agent = buildAgentFromConfig(agentCfg);

            FC_StepRequest request = (FC_StepRequest) JSON.deserialize(
                stepRequestJson, FC_StepRequest.class
            );

            FC_AgentExecutorStep executor = new FC_AgentExecutorStep(agent);
            return executor.step(request);

        } catch (Exception e) {
            FC_StepRequest errReq = new FC_StepRequest();
            errReq.errorMessage   = e.getMessage();
            return errReq;
        }
    }

    /**
     * Enqueues a crew for fully asynchronous execution via FC_CrewQueueable.
     * Results are pushed back via FC_CrewEvent__e Platform Event.
     * Use this for multi-task, multi-agent crews where governor limits are a concern.
     *
     * @param crewConfigJson  Same JSON schema as runCrewFromConfig (SEQUENTIAL only)
     * @param correlationId   Optional ID to correlate the async result (e.g., a record Id)
     * @return The Queueable job Id
     */
    @AuraEnabled(cacheable=false)
    public static String enqueueCrewAsync(String crewConfigJson, String correlationId) {
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(crewConfigJson);
            FC_Crew crew = buildCrewFromConfig(config);

            Map<String, Object> inputs = config.containsKey('inputs')
                ? (Map<String, Object>) config.get('inputs')
                : null;

            Id jobId = FC_CrewQueueable.enqueue(crew, inputs, correlationId);
            return jobId;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─── Private: Crew Builder from JSON Config ───────────────────────────────

    private static FC_Crew buildCrewFromConfig(Map<String, Object> config) {
        String crewName = (String) config.get('crewName');
        String processStr = (String) config.get('process');
        Boolean verbose   = config.containsKey('verbose') && (Boolean) config.get('verbose');

        FC_Process.Type process = (processStr == 'HIERARCHICAL')
            ? FC_Process.Type.HIERARCHICAL
            : FC_Process.Type.SEQUENTIAL;

        FC_Crew.Builder crewBuilder = new FC_Crew.Builder(String.isNotBlank(crewName) ? crewName : 'Crew')
            .process(process)
            .verbose(verbose);

        // Build agents
        List<Object> agentConfigs = (List<Object>) config.get('agents');
        if (agentConfigs != null) {
            for (Object agentObj : agentConfigs) {
                crewBuilder.agent(buildAgentFromConfig((Map<String, Object>) agentObj));
            }
        }

        // Build tasks
        List<Object> taskConfigs = (List<Object>) config.get('tasks');
        if (taskConfigs != null) {
            for (Object taskObj : taskConfigs) {
                crewBuilder.task(buildTaskFromConfig((Map<String, Object>) taskObj));
            }
        }

        return crewBuilder.build();
    }

    private static FC_Agent buildAgentFromConfig(Map<String, Object> cfg) {
        FC_Agent.Builder b = new FC_Agent.Builder((String) cfg.get('role'))
            .goal((String) cfg.get('goal'))
            .backstory((String) cfg.get('backstory'));

        List<Object> toolClasses = (List<Object>) cfg.get('toolClasses');
        if (toolClasses != null) {
            for (Object cls : toolClasses) {
                if (String.isNotBlank((String) cls)) {
                    b.tool(FC_Tool.fromClassName((String) cls));
                }
            }
        }

        if (cfg.containsKey('maxIterations')) {
            b.maxIterations(Integer.valueOf(cfg.get('maxIterations')));
        }

        return b.build();
    }

    private static FC_Task buildTaskFromConfig(Map<String, Object> cfg) {
        FC_Task.Builder b = new FC_Task.Builder((String) cfg.get('name'))
            .description((String) cfg.get('description'))
            .expectedOutput((String) cfg.get('expectedOutput'))
            .assignToAgent((String) cfg.get('assignToAgent'));

        List<Object> contextTasks = (List<Object>) cfg.get('contextTasks');
        if (contextTasks != null) {
            for (Object ct : contextTasks) {
                b.withContext((String) ct);
            }
        }

        return b.build();
    }

    // ─── Private: DTO Mapping ─────────────────────────────────────────────────

    private static CrewResultDTO toDTO(FC_CrewResult result) {
        CrewResultDTO dto        = new CrewResultDTO();
        dto.success              = result.success;
        dto.crewName             = result.crewName;
        dto.finalOutput          = result.finalOutput;
        dto.errorMessage         = result.errorMessage;
        dto.executionTimeMs      = result.totalExecutionTimeMs;
        dto.taskCount            = result.taskResults.size();
        dto.successfulTasks      = result.successfulTaskCount();
        dto.totalToolCalls       = result.totalToolCalls();
        dto.tasks                = new List<TaskResultDTO>();
        dto.logs                 = collectLogs();

        for (FC_TaskResult tr : result.taskResults) {
            dto.tasks.add(toTaskDTO(tr));
        }
        return dto;
    }

    private static TaskResultDTO toTaskDTO(FC_TaskResult tr) {
        TaskResultDTO dto    = new TaskResultDTO();
        dto.taskName         = tr.taskName;
        dto.agentRole        = tr.agentRole;
        dto.output           = tr.output;
        dto.success          = tr.success;
        dto.errorMessage     = tr.errorMessage;
        dto.executionTimeMs  = tr.executionTimeMs;
        dto.toolCallCount    = tr.toolCallCount();
        dto.steps            = new List<StepResultDTO>();

        for (FC_StepResult step : tr.steps) {
            dto.steps.add(toStepDTO(step));
        }
        return dto;
    }

    private static StepResultDTO toStepDTO(FC_StepResult step) {
        StepResultDTO dto = new StepResultDTO();
        dto.stepType      = step.stepType != null ? step.stepType.name() : null;
        dto.thought       = step.thought;
        dto.toolName      = step.toolName;
        dto.toolResult    = step.toolResult;
        dto.answer        = step.answer;
        dto.success       = step.success;
        dto.error         = step.errorMessage;
        return dto;
    }

    private static List<String> collectLogs() {
        List<String> logLines = new List<String>();
        for (FC_Logger.LogEntry entry : FC_Logger.getBuffer()) {
            logLines.add(entry.toString());
        }
        return logLines;
    }
}
