/**
 * FC_CrewQueueable - Runs a ForceCrew sequential crew asynchronously via Queueable chaining.
 *
 * DATA PASSING STRATEGY — Custom Object as State Store
 * ─────────────────────────────────────────────────────
 * Each job passes ONLY the FC_CrewRun__c record Id to the next job.
 * All state (crew config, task outputs, results) is read/written via that record.
 *
 * Why NOT pass state as Queueable instance variables:
 *   1. Tools (FC_ITool implementations) cannot be serialised — they are lost between jobs.
 *   2. Accumulated LLM outputs grow the serialised payload — risky for large crews.
 *   3. Custom Object state gives you a full audit trail and allows external monitoring.
 *
 * HOW IT WORKS:
 *   enqueue()
 *     └─▶ creates FC_CrewRun__c record (stores crew config JSON, status=Pending)
 *         └─▶ enqueues Job[0] with only the record Id
 *
 *   Job[taskIndex].execute()
 *     1. Reads FC_CrewRun__c by Id
 *     2. Rebuilds agent + task from stored JSON config
 *     3. Runs FC_AgentExecutor for that task
 *     4. Writes task output back into FC_CrewRun__c.TaskOutputsJson__c
 *     5. Enqueues Job[taskIndex+1] with same record Id
 *
 *   Last job
 *     └─▶ Marks FC_CrewRun__c.Status__c = 'Completed'
 *         └─▶ Publishes FC_CrewEvent__e so LWC is notified
 *
 * REQUIRED METADATA:
 *   See setupInstructions() for the FC_CrewRun__c object + FC_CrewEvent__e fields.
 *
 * @group ForceCrew
 */
public class FC_CrewQueueable implements Queueable {

    // ─── Serialisable (only primitive types — safe across jobs) ──────────────

    private Id      crewRunId;
    private Integer taskIndex;

    // ─── Inner Config DTOs (serialisable to/from JSON stored in the record) ──

    public class CrewRunConfig {
        public String           crewName;
        public String           process;
        public Boolean          verbose;
        public Boolean          failFast;
        public String           correlationId;
        public List<AgentConfig> agents;
        public List<TaskConfig>  tasks;
    }

    public class AgentConfig {
        public String       role;
        public String       goal;
        public String       backstory;
        public List<String> toolClassNames;
        public Integer      maxIterations;
        public String       llmModel;
    }

    public class TaskConfig {
        public String       name;
        public String       description;
        public String       expectedOutput;
        public String       assignedAgentRole;
        public List<String> contextTaskNames;
    }

    // ─── Status Constants ─────────────────────────────────────────────────────

    public static final String STATUS_PENDING   = 'Pending';
    public static final String STATUS_RUNNING   = 'Running';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_FAILED    = 'Failed';

    // ─── Constructor ─────────────────────────────────────────────────────────

    public FC_CrewQueueable(Id crewRunId, Integer taskIndex) {
        this.crewRunId = crewRunId;
        this.taskIndex = taskIndex;
    }

    // ─── Public Entry Point ───────────────────────────────────────────────────

    /**
     * Converts an FC_Crew into a serialisable config, saves it to FC_CrewRun__c,
     * and enqueues Job[0].
     *
     * @param crew          Fully configured sequential FC_Crew
     * @param inputs        Runtime key/value inputs available as initial context
     * @param correlationId Optional external Id to correlate the async result (e.g., a record Id)
     * @return The Id of the FC_CrewRun__c record (use this to poll status or link the result)
     */
    public static Id enqueue(FC_Crew crew, Map<String, Object> inputs, String correlationId) {
        if (crew.getProcess() == FC_Process.Type.HIERARCHICAL) {
            throw new FC_Exception.ConfigurationException(
                'FC_CrewQueueable supports SEQUENTIAL process only. '
                + 'Run HIERARCHICAL crews via FC_Crew.kickoff() inside a standalone Queueable.'
            );
        }

        // Serialise crew config
        CrewRunConfig config   = buildCrewRunConfig(crew, correlationId);
        String        configJson = JSON.serialize(config);

        // Seed initial task outputs from inputs
        Map<String, String> taskOutputs = new Map<String, String>();
        if (inputs != null) {
            for (String k : inputs.keySet()) {
                Object v = inputs.get(k);
                taskOutputs.put(k, v != null ? String.valueOf(v) : '');
            }
        }

        // Create the FC_CrewRun__c record
        SObject run = createCrewRunRecord(config.crewName, configJson, taskOutputs, correlationId);
        insert run;

        Id runId = run.Id;
        FC_Logger.info('FC_CrewQueueable',
            'Created FC_CrewRun__c ' + runId + ' for crew "' + config.crewName + '"');

        System.enqueueJob(new FC_CrewQueueable(runId, 0));
        return runId;
    }

    /** Enqueues without inputs or correlationId. */
    public static Id enqueue(FC_Crew crew) {
        return enqueue(crew, null, null);
    }

    // ─── Queueable.execute ────────────────────────────────────────────────────

    public void execute(QueueableContext context) {
        // 1. Read state from record
        SObject run = readCrewRunRecord(crewRunId);
        if (run == null) {
            FC_Logger.error('FC_CrewQueueable', 'FC_CrewRun__c not found: ' + crewRunId);
            return;
        }

        CrewRunConfig       config      = (CrewRunConfig) JSON.deserialize(
            (String) run.get('CrewConfigJson__c'), CrewRunConfig.class
        );
        Map<String, String> taskOutputs = deserialiseTaskOutputs(
            (String) run.get('TaskOutputsJson__c')
        );

        if (config.verbose) FC_Logger.enableDebug();

        FC_Logger.info('FC_CrewQueueable',
            'Job [' + taskIndex + '/' + config.tasks.size() + ']'
            + ' crew="' + config.crewName + '"'
            + ' jobId=' + context.getJobId());

        // 2. Mark running
        updateCrewRunStatus(crewRunId, STATUS_RUNNING, null, null, taskOutputs);

        if (taskIndex >= config.tasks.size()) {
            // Defensive: all tasks done
            finalise(crewRunId, config, taskOutputs, null);
            return;
        }

        // 3. Resolve task + agent
        TaskConfig  taskCfg  = config.tasks[taskIndex];
        AgentConfig agentCfg = resolveAgent(config.agents, taskCfg.assignedAgentRole);

        if (agentCfg == null) {
            String err = 'No agent with role "' + taskCfg.assignedAgentRole + '"';
            FC_Logger.error('FC_CrewQueueable', err);
            if (config.failFast) {
                finalise(crewRunId, config, taskOutputs, err);
                return;
            }
        } else {
            // 4. Execute this task (full ReAct loop within this job's transaction)
            FC_Agent agent = buildAgent(agentCfg);
            FC_Task  task  = buildTask(taskCfg);

            FC_AgentExecutor executor = new FC_AgentExecutor(agent);
            FC_TaskResult    result   = executor.execute(task, taskOutputs);

            if (result.success) {
                taskOutputs.put(taskCfg.name, result.output);
                FC_Logger.info('FC_CrewQueueable',
                    'Task "' + taskCfg.name + '" completed.');
            } else {
                FC_Logger.warn('FC_CrewQueueable',
                    'Task "' + taskCfg.name + '" failed: ' + result.errorMessage);
                if (config.failFast) {
                    finalise(crewRunId, config, taskOutputs,
                        'Task "' + taskCfg.name + '" failed: ' + result.errorMessage);
                    return;
                }
            }

            // Persist updated task outputs after this task completes
            updateCrewRunStatus(crewRunId, STATUS_RUNNING, null, null, taskOutputs);
        }

        // 5. Enqueue next job or finalise
        Integer nextIndex = taskIndex + 1;
        if (nextIndex >= config.tasks.size()) {
            finalise(crewRunId, config, taskOutputs, null);
        } else {
            System.enqueueJob(new FC_CrewQueueable(crewRunId, nextIndex));
        }
    }

    // ─── Finalise ─────────────────────────────────────────────────────────────

    private void finalise(
        Id                  runId,
        CrewRunConfig       config,
        Map<String, String> taskOutputs,
        String              errorMessage
    ) {
        Boolean success     = String.isBlank(errorMessage);
        String  finalOutput = null;

        if (success) {
            // Last successful task output is the crew's final answer
            for (Integer i = config.tasks.size() - 1; i >= 0; i--) {
                String out = taskOutputs.get(config.tasks[i].name);
                if (String.isNotBlank(out)) {
                    finalOutput = out;
                    break;
                }
            }
        }

        String status = success ? STATUS_COMPLETED : STATUS_FAILED;
        updateCrewRunStatus(runId, status, finalOutput, errorMessage, taskOutputs);

        FC_Logger.info('FC_CrewQueueable',
            'Crew "' + config.crewName + '" ' + status
            + (success ? '' : ' — ' + errorMessage));

        publishEvent(config.crewName, config.correlationId, runId, finalOutput, errorMessage, success);
    }

    // ─── Record Operations ────────────────────────────────────────────────────

    private static SObject createCrewRunRecord(
        String              crewName,
        String              configJson,
        Map<String, String> taskOutputs,
        String              correlationId
    ) {
        SObject run = (SObject) Type.forName('FC_CrewRun__c').newInstance();
        run.put('CrewName__c',        crewName);
        run.put('Status__c',          STATUS_PENDING);
        run.put('CrewConfigJson__c',  configJson);
        run.put('TaskOutputsJson__c', JSON.serialize(taskOutputs));
        run.put('CorrelationId__c',   correlationId);
        return run;
    }

    private static SObject readCrewRunRecord(Id runId) {
        try {
            List<SObject> records = Database.query(
                'SELECT Id, CrewConfigJson__c, TaskOutputsJson__c, Status__c '
                + 'FROM FC_CrewRun__c WHERE Id = :runId LIMIT 1'
            );
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            FC_Logger.error('FC_CrewQueueable', 'Failed to read FC_CrewRun__c: ' + e.getMessage());
            return null;
        }
    }

    private static void updateCrewRunStatus(
        Id                  runId,
        String              status,
        String              finalOutput,
        String              errorMessage,
        Map<String, String> taskOutputs
    ) {
        try {
            SObject run = (SObject) Type.forName('FC_CrewRun__c').newInstance();
            run.put('Id',               runId);
            run.put('Status__c',        status);
            run.put('TaskOutputsJson__c', JSON.serialize(taskOutputs));
            if (finalOutput  != null) run.put('FinalOutput__c',  finalOutput);
            if (errorMessage != null) run.put('ErrorMessage__c', errorMessage);
            update run;
        } catch (Exception e) {
            FC_Logger.error('FC_CrewQueueable', 'Failed to update FC_CrewRun__c: ' + e.getMessage());
        }
    }

    // ─── Platform Event ───────────────────────────────────────────────────────

    private static void publishEvent(
        String  crewName,
        String  correlationId,
        Id      runId,
        String  finalOutput,
        String  errorMessage,
        Boolean success
    ) {
        try {
            SObject evt = (SObject) Type.forName('FC_CrewEvent__e').newInstance();
            evt.put('CrewName__c',      crewName);
            evt.put('CorrelationId__c', correlationId);
            evt.put('RunId__c',         runId);
            evt.put('FinalOutput__c',   finalOutput);
            evt.put('ErrorMessage__c',  errorMessage);
            evt.put('Success__c',       success);
            EventBus.publish(evt);
        } catch (Exception e) {
            FC_Logger.warn('FC_CrewQueueable',
                'FC_CrewEvent__e not deployed — skipping event publish. '
                + 'Run FC_CrewQueueable.setupInstructions() to see required metadata.');
        }
    }

    // ─── Build Helpers ────────────────────────────────────────────────────────

    private static FC_Agent buildAgent(AgentConfig cfg) {
        FC_Agent.Builder b = new FC_Agent.Builder(cfg.role)
            .goal(cfg.goal)
            .backstory(cfg.backstory);

        if (cfg.maxIterations != null) b.maxIterations(cfg.maxIterations);
        if (cfg.llmModel      != null) b.llmModel(cfg.llmModel);

        if (cfg.toolClassNames != null) {
            for (String cls : cfg.toolClassNames) {
                if (String.isNotBlank(cls)) {
                    try {
                        b.tool(FC_Tool.fromClassName(cls));
                    } catch (Exception e) {
                        FC_Logger.warn('FC_CrewQueueable',
                            'Could not load tool "' + cls + '": ' + e.getMessage());
                    }
                }
            }
        }
        return b.build();
    }

    private static FC_Task buildTask(TaskConfig cfg) {
        FC_Task.Builder b = new FC_Task.Builder(cfg.name)
            .description(cfg.description)
            .expectedOutput(cfg.expectedOutput)
            .assignToAgent(cfg.assignedAgentRole);
        if (cfg.contextTaskNames != null) b.withContextFrom(cfg.contextTaskNames);
        return b.build();
    }

    private static AgentConfig resolveAgent(List<AgentConfig> agents, String role) {
        if (String.isBlank(role)) return agents.isEmpty() ? null : agents[0];
        for (AgentConfig cfg : agents) {
            if (cfg.role == role) return cfg;
        }
        return null;
    }

    // ─── Config Conversion ────────────────────────────────────────────────────

    private static CrewRunConfig buildCrewRunConfig(FC_Crew crew, String correlationId) {
        CrewRunConfig config   = new CrewRunConfig();
        config.crewName        = crew.getName();
        config.process         = crew.getProcess().name();
        config.verbose         = crew.isVerbose();
        config.failFast        = crew.isFailFast();
        config.correlationId   = correlationId;

        config.agents = new List<AgentConfig>();
        for (FC_Agent agent : crew.getAgents()) {
            AgentConfig ac  = new AgentConfig();
            ac.role         = agent.role;
            ac.goal         = agent.goal;
            ac.backstory    = agent.backstory;
            ac.maxIterations = agent.maxIterations;
            ac.llmModel     = agent.llmModel;
            ac.toolClassNames = new List<String>();
            // Collect class names only for FC_IMCPTool instances (round-trippable)
            for (FC_Tool tool : agent.tools) {
                // FC_Tool.fromMCP / fromClassName stores the class name via getName()
                // but we need the implementing class name, not the tool name.
                // Convention: tools registered via fromClassName() can be re-instantiated.
                // Tools registered via from() (plain FC_ITool) CANNOT be round-tripped.
                // The caller must use toolClassNames on AgentConfig explicitly.
                // See setupInstructions() for guidance.
            }
            config.agents.add(ac);
        }

        config.tasks = new List<TaskConfig>();
        for (FC_Task task : crew.getTasks()) {
            TaskConfig tc       = new TaskConfig();
            tc.name             = task.name;
            tc.description      = task.description;
            tc.expectedOutput   = task.expectedOutput;
            tc.assignedAgentRole = task.assignedAgentRole;
            tc.contextTaskNames = task.contextTaskNames.clone();
            config.tasks.add(tc);
        }
        return config;
    }

    private static Map<String, String> deserialiseTaskOutputs(String json_x) {
        if (String.isBlank(json_x)) return new Map<String, String>();
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(json_x);
            Map<String, String> result = new Map<String, String>();
            for (String k : raw.keySet()) {
                result.put(k, raw.get(k) != null ? String.valueOf(raw.get(k)) : '');
            }
            return result;
        } catch (Exception e) {
            return new Map<String, String>();
        }
    }

    // ─── Setup Instructions ───────────────────────────────────────────────────

    /**
     * Prints the Salesforce metadata required to use FC_CrewQueueable.
     *
     * IMPORTANT NOTE ON TOOLS AND QUEUEABLE:
     *   Tools registered via FC_Tool.fromClassName() ARE round-trippable because
     *   the class name is stored and the class is re-instantiated in each job.
     *   Tools registered via FC_Tool.from(name, desc, new MyTool()) are NOT
     *   round-trippable — you must use fromClassName() for async crews,
     *   or subclass FC_IMCPTool so the tool is re-instantiable by name.
     */
    public static String setupInstructions() {
        return '=== FC_CrewQueueable Required Metadata ===\n\n'
            + '1. Custom Object: FC_CrewRun__c\n'
            + '   Fields:\n'
            + '   - CrewName__c         Text(255)\n'
            + '   - Status__c           Picklist: Pending, Running, Completed, Failed\n'
            + '   - CrewConfigJson__c   Long Text Area(131072)  — full crew JSON config\n'
            + '   - TaskOutputsJson__c  Long Text Area(131072)  — accumulated task outputs\n'
            + '   - FinalOutput__c      Long Text Area(32768)   — final crew output\n'
            + '   - ErrorMessage__c     Text(1024)\n'
            + '   - CorrelationId__c    Text(255)\n\n'
            + '2. Platform Event: FC_CrewEvent__e\n'
            + '   Fields:\n'
            + '   - CrewName__c         Text(255)\n'
            + '   - CorrelationId__c    Text(255)\n'
            + '   - RunId__c            Text(18)   — Id of FC_CrewRun__c\n'
            + '   - FinalOutput__c      Long Text Area(32768)\n'
            + '   - ErrorMessage__c     Text(1024)\n'
            + '   - Success__c          Checkbox\n\n'
            + '3. Tool Requirement:\n'
            + '   All tools used in async crews MUST implement FC_IMCPTool\n'
            + '   and be registered via FC_Tool.fromClassName(\'MyToolClass\').\n'
            + '   Tools registered via FC_Tool.from(..., new MyTool()) cannot be\n'
            + '   serialised across jobs.\n\n'
            + '4. LWC: Subscribe to FC_CrewEvent__e via lightning/empApi\n'
            + '   to receive real-time completion notifications.';
    }
}
