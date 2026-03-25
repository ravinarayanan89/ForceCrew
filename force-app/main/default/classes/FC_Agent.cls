/**
 * FC_Agent - An AI agent with a role, goal, backstory, and set of tools.
 * Use the Builder to construct immutable agent instances.
 *
 * An agent is the unit of intelligence in ForceCrew.
 * Each agent has a unique role within its crew, a clearly defined goal that guides its behaviour,
 * and a backstory that shapes its tone and domain expertise.
 * Agents execute tasks via the ReAct loop in FC_AgentExecutor.
 *
 * Example:
 *   FC_Agent analyst = new FC_Agent.Builder('Salesforce Data Analyst')
 *       .goal('Query Salesforce data and surface key business insights.')
 *       .backstory('You are a certified Salesforce analyst with 10 years of CRM experience.')
 *       .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
 *       .tool(FC_Tool.fromMCP(new FC_SampleDescribeTool()))
 *       .maxIterations(8)
 *       .verbose(true)
 *       .build();
 *
 * @group ForceCrew
 */
public class FC_Agent {

    private static final Integer DEFAULT_MAX_ITERATIONS = 10;

    public String         role            { get; private set; }
    public String         goal            { get; private set; }
    public String         backstory       { get; private set; }
    public List<FC_Tool>  tools           { get; private set; }
    public Integer        maxIterations   { get; private set; }
    public Boolean        verbose         { get; private set; }
    public Boolean        allowDelegation { get; private set; }
    public String         llmModel        { get; private set; }

    private FC_Agent() {}

    // ─── Builder ──────────────────────────────────────────────────────────────

    public class Builder {
        private FC_Agent agent;

        /**
         * @param role The agent's unique role label (e.g., 'Researcher', 'Data Analyst').
         *             Used to assign tasks and identify the agent within a crew.
         */
        public Builder(String role) {
            if (String.isBlank(role)) {
                throw new FC_Exception.ConfigurationException('Agent role cannot be blank');
            }
            agent                 = new FC_Agent();
            agent.role            = role;
            agent.tools           = new List<FC_Tool>();
            agent.maxIterations   = DEFAULT_MAX_ITERATIONS;
            agent.verbose         = false;
            agent.allowDelegation = false;
        }

        /**
         * The agent's objective — drives its reasoning during task execution.
         * Should be a concise statement of what the agent is trying to achieve.
         */
        public Builder goal(String goal) {
            agent.goal = goal;
            return this;
        }

        /**
         * The agent's background persona — shapes the tone and domain focus of its responses.
         * Written in second person: "You are a..."
         */
        public Builder backstory(String backstory) {
            agent.backstory = backstory;
            return this;
        }

        /** Registers a single tool with this agent. */
        public Builder tool(FC_Tool tool) {
            if (tool != null) {
                agent.tools.add(tool);
            }
            return this;
        }

        /** Registers multiple tools at once. */
        public Builder tools(List<FC_Tool> toolList) {
            if (toolList != null) {
                for (FC_Tool t : toolList) {
                    if (t != null) agent.tools.add(t);
                }
            }
            return this;
        }

        /**
         * Maximum ReAct loop iterations before throwing FC_Exception.MaxIterationsException.
         * Prevents infinite loops on ambiguous tasks. Default: 10.
         */
        public Builder maxIterations(Integer maxIter) {
            agent.maxIterations = maxIter > 0 ? maxIter : DEFAULT_MAX_ITERATIONS;
            return this;
        }

        /**
         * Enables verbose/debug logging for this agent's execution.
         * Raw LLM responses will be written to the FC_Logger buffer.
         */
        public Builder verbose(Boolean verbose) {
            agent.verbose = verbose;
            if (verbose) FC_Logger.enableDebug();
            return this;
        }

        /**
         * Allows this agent to delegate sub-tasks to other agents (hierarchical process only).
         */
        public Builder allowDelegation(Boolean allow) {
            agent.allowDelegation = allow;
            return this;
        }

        /**
         * Overrides the LLM model for this agent.
         * Use FC_ModelsAPIService.MODEL_* constants.
         * If not set, defaults to sfdc_ai__DefaultGPT4Omni.
         */
        public Builder llmModel(String model) {
            agent.llmModel = model;
            return this;
        }

        public FC_Agent build() {
            if (String.isBlank(agent.goal)) {
                agent.goal = 'Complete the assigned task to the best of your ability.';
            }
            if (String.isBlank(agent.backstory)) {
                agent.backstory = 'You are a helpful AI assistant specialised in ' + agent.role + '.';
            }
            return agent;
        }
    }

    // ─── Tool Lookup ──────────────────────────────────────────────────────────

    /** Returns the tool with the exact given name, or null if not found. */
    public FC_Tool getTool(String name) {
        for (FC_Tool tool : tools) {
            if (tool.getName() == name) {
                return tool;
            }
        }
        return null;
    }

    public Boolean hasTools() {
        return !tools.isEmpty();
    }

    // ─── System Prompt ────────────────────────────────────────────────────────

    /**
     * Builds the full system prompt injected at the start of every LLM conversation.
     * Includes the agent's identity (role, goal, backstory), the tool schema (if any tools),
     * and strict JSON response format rules.
     */
    public String buildSystemPrompt() {
        String toolSection = buildToolSection();
        String formatSection = buildResponseFormatSection();

        return 'You are a ' + role + '.\n\n'
            + '## Your Goal\n' + goal + '\n\n'
            + '## Your Backstory\n' + backstory
            + toolSection
            + formatSection;
    }

    private String buildToolSection() {
        if (tools.isEmpty()) return '';

        List<Map<String, Object>> toolDefs = new List<Map<String, Object>>();
        for (FC_Tool tool : tools) {
            toolDefs.add(tool.toDefinition());
        }

        return '\n\n## Execution Environment\n'
            + 'You are running inside a custom Salesforce Apex agent runtime. '
            + 'Tool calls are made by returning a JSON TOOL_CALL response — this IS the real, '
            + 'working mechanism for invoking Salesforce APIs. The tools below are implemented as '
            + 'Apex classes that execute against a live Salesforce org. There is no other tool-calling '
            + 'mechanism available. Do NOT say tools are unavailable — they are real and ready.\n\n'
            + '## Available Tools\n'
            + 'The following tools are registered and callable in this runtime:\n'
            + JSON.serializePretty(toolDefs);
    }

    private String buildResponseFormatSection() {
        if (tools.isEmpty()) {
            return '\n\n## Response Format\n'
                + 'Respond with ONLY a valid JSON object — no markdown fences, no extra text:\n'
                + '{\n'
                + '  "thought": "<your reasoning>",\n'
                + '  "action": "FINAL_ANSWER",\n'
                + '  "answer": "<your complete response>"\n'
                + '}';
        }

        return '\n\n## How to Call a Tool\n'
            + 'To invoke a tool, respond with ONLY this JSON (no prose, no markdown fences):\n'
            + '{\n'
            + '  "thought": "<your reasoning — what you are doing and why>",\n'
            + '  "action": "TOOL_CALL",\n'
            + '  "tool": "<exact tool name from the list above>",\n'
            + '  "parameters": { "<param_name>": "<value>" }\n'
            + '}\n'
            + 'The runtime will execute the tool and return a TOOL_RESULT message. Then decide your next step.\n\n'
            + '## How to Return a Final Answer\n'
            + 'Once you have gathered all needed data, respond with ONLY this JSON:\n'
            + '{\n'
            + '  "thought": "<your final reasoning>",\n'
            + '  "action": "FINAL_ANSWER",\n'
            + '  "answer": "<your complete, well-formatted response>"\n'
            + '}\n\n'
            + '## Rules\n'
            + '- NEVER output plain text outside JSON. Every response must be valid JSON.\n'
            + '- NEVER say "I don\'t have access to tools" or "no tools are available" — the tools above ARE available.\n'
            + '- Only use TOOL_CALL when you need data or must perform an action.\n'
            + '- Only use FINAL_ANSWER when you have everything needed to answer fully.\n'
            + '- Tool names must exactly match one of the names in the Available Tools section.\n'
            + '- Never guess parameter values — use only information from the task or tool results.';
    }
}
