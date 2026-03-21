/**
 * FC_Crew - The central orchestrator of the ForceCrew framework.
 *
 * A crew is a team of FC_Agent instances that collaborate to complete a set of FC_Task instances.
 * Crews support two execution processes:
 *   - SEQUENTIAL  (default): tasks run in order; outputs chain as context
 *   - HIERARCHICAL: a manager LLM dynamically delegates tasks to the right agents
 *
 * Use the Builder to construct and then call kickoff() to execute.
 *
 * Example — Sequential crew:
 *   FC_CrewResult result = new FC_Crew.Builder('Revenue Intelligence Crew')
 *       .agent(new FC_Agent.Builder('Salesforce Analyst')
 *           .goal('Query and analyse Salesforce revenue data.')
 *           .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
 *           .build())
 *       .agent(new FC_Agent.Builder('Executive Writer')
 *           .goal('Translate data insights into crisp executive narratives.')
 *           .build())
 *       .task(new FC_Task.Builder('Pull Revenue Data')
 *           .description('Query the top 10 accounts by AnnualRevenue.')
 *           .expectedOutput('JSON list of account names and revenues.')
 *           .assignToAgent('Salesforce Analyst')
 *           .build())
 *       .task(new FC_Task.Builder('Write Briefing')
 *           .description('Turn the revenue data into a 3-bullet executive briefing.')
 *           .expectedOutput('Three concise bullet points.')
 *           .assignToAgent('Executive Writer')
 *           .withContext('Pull Revenue Data')
 *           .build())
 *       .verbose(true)
 *       .build()
 *       .kickoff();
 *
 * @group ForceCrew
 */
public with sharing class FC_Crew {

    private String            name;
    private FC_Process.Type   process;
    private List<FC_Agent>    agents;
    private List<FC_Task>     tasks;
    private Boolean           verbose;
    private Boolean           failFast;
    private String            managerLlmModel;

    private FC_Crew() {}

    // ─── Builder ──────────────────────────────────────────────────────────────

    public class Builder {
        private FC_Crew crew;

        public Builder(String name) {
            if (String.isBlank(name)) {
                throw new FC_Exception.ConfigurationException('Crew name cannot be blank');
            }
            crew                = new FC_Crew();
            crew.name           = name;
            crew.agents         = new List<FC_Agent>();
            crew.tasks          = new List<FC_Task>();
            crew.process        = FC_Process.Type.SEQUENTIAL;
            crew.verbose        = false;
            crew.failFast       = true;
        }

        /**
         * Sets the execution process. Defaults to SEQUENTIAL.
         * Use FC_Process.Type.HIERARCHICAL for dynamic LLM-driven orchestration.
         */
        public Builder process(FC_Process.Type processType) {
            crew.process = processType;
            return this;
        }

        public Builder agent(FC_Agent agent) {
            if (agent != null) crew.agents.add(agent);
            return this;
        }

        public Builder agents(List<FC_Agent> agentList) {
            if (agentList != null) {
                for (FC_Agent a : agentList) {
                    if (a != null) crew.agents.add(a);
                }
            }
            return this;
        }

        public Builder task(FC_Task task) {
            if (task != null) crew.tasks.add(task);
            return this;
        }

        public Builder tasks(List<FC_Task> taskList) {
            if (taskList != null) {
                for (FC_Task t : taskList) {
                    if (t != null) crew.tasks.add(t);
                }
            }
            return this;
        }

        /**
         * Enables verbose/debug output. Raw LLM responses will be written to FC_Logger.
         */
        public Builder verbose(Boolean verbose) {
            crew.verbose = verbose;
            if (verbose) FC_Logger.enableDebug();
            return this;
        }

        /**
         * When true (default), any task failure aborts the entire crew.
         * When false, the crew logs the failure and continues with remaining tasks.
         */
        public Builder failFast(Boolean failFast) {
            crew.failFast = failFast;
            return this;
        }

        /**
         * Sets the LLM model used by the manager agent in HIERARCHICAL process.
         * Defaults to sfdc_ai__DefaultGPT4Omni if not set.
         */
        public Builder managerLlmModel(String model) {
            crew.managerLlmModel = model;
            return this;
        }

        public FC_Crew build() {
            if (crew.agents.isEmpty()) {
                throw new FC_Exception.ConfigurationException(
                    'Crew "' + crew.name + '" must have at least one agent.'
                );
            }
            if (crew.tasks.isEmpty()) {
                throw new FC_Exception.ConfigurationException(
                    'Crew "' + crew.name + '" must have at least one task.'
                );
            }
            if (crew.process == FC_Process.Type.HIERARCHICAL
                && String.isBlank(crew.managerLlmModel)) {
                crew.managerLlmModel = FC_ModelsAPIService.MODEL_GPT4O;
            }
            return crew;
        }
    }

    // ─── Kickoff ──────────────────────────────────────────────────────────────

    /**
     * Starts the crew execution with runtime inputs.
     * Inputs are available to all tasks as named context variables.
     *
     * @param inputs Key-value pairs available as context (e.g., {'accountId': '001...'})
     */
    public FC_CrewResult kickoff(Map<String, Object> inputs) {
        validate();
        return new FC_CrewExecutor(this).execute(inputs);
    }

    /** Starts the crew with no inputs. */
    public FC_CrewResult kickoff() {
        return kickoff(null);
    }

    // ─── Validation ───────────────────────────────────────────────────────────

    private void validate() {
        Set<String> agentRoles = new Set<String>();
        for (FC_Agent agent : agents) {
            if (agentRoles.contains(agent.role)) {
                throw new FC_Exception.ConfigurationException(
                    'Duplicate agent role "' + agent.role + '" in crew "' + name
                    + '". Agent roles must be unique within a crew.'
                );
            }
            agentRoles.add(agent.role);
        }

        Set<String> taskNames = new Set<String>();
        for (FC_Task task : tasks) {
            if (taskNames.contains(task.name)) {
                throw new FC_Exception.ConfigurationException(
                    'Duplicate task name "' + task.name + '" in crew "' + name
                    + '". Task names must be unique within a crew.'
                );
            }
            taskNames.add(task.name);

            if (String.isNotBlank(task.assignedAgentRole)
                && !agentRoles.contains(task.assignedAgentRole)) {
                throw new FC_Exception.AgentNotFoundException(
                    'Task "' + task.name + '" is assigned to agent role "'
                    + task.assignedAgentRole + '" which is not registered in crew "' + name + '".'
                );
            }
        }
    }

    // ─── Accessors ────────────────────────────────────────────────────────────

    public String           getName()            { return name; }
    public FC_Process.Type  getProcess()         { return process; }
    public List<FC_Agent>   getAgents()          { return agents.clone(); }
    public List<FC_Task>    getTasks()           { return tasks.clone(); }
    public Boolean          isVerbose()          { return verbose; }
    public Boolean          isFailFast()         { return failFast; }
    public String           getManagerLlmModel() { return managerLlmModel; }

    /** Returns the agent with the exact given role, or null if not found. */
    public FC_Agent getAgent(String role) {
        for (FC_Agent agent : agents) {
            if (agent.role == role) return agent;
        }
        return null;
    }

    /** Returns the task with the exact given name, or null if not found. */
    public FC_Task getTask(String taskName) {
        for (FC_Task task : tasks) {
            if (task.name == taskName) return task;
        }
        return null;
    }
}
