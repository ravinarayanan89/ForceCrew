/**
 * ForceCrew - The main entry-point facade for the ForceCrew framework.
 *
 * ForceCrew is a crewAI-inspired multi-agent orchestration framework for Salesforce Apex.
 * It enables you to build teams of AI agents (powered by the Salesforce Models API)
 * that collaborate to complete complex, multi-step tasks using a collection of tools.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                         ForceCrew Architecture                          │
 * │                                                                         │
 * │  FC_Crew  ──── FC_Agent(s) ──── FC_Tool(s) ──── FC_ITool / FC_IMCPTool │
 * │     │               │                                                   │
 * │     └── FC_Task(s) ─┘ (assigned to agents)                             │
 * │                                                                         │
 * │  kickoff() → FC_CrewExecutor → FC_AgentExecutor (ReAct loop per task)  │
 * │                 │                                                       │
 * │           SEQUENTIAL  or  HIERARCHICAL (FC_ManagerAgent)               │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Quick-start example:
 *
 *   // 1. Build tools
 *   FC_Tool queryTool    = FC_Tool.fromMCP(new FC_SampleSOQLTool());
 *   FC_Tool describeTool = FC_Tool.fromMCP(new FC_SampleDescribeTool());
 *
 *   // 2. Build agents
 *   FC_Agent analyst = new FC_Agent.Builder('Salesforce Analyst')
 *       .goal('Query Salesforce data and uncover insights.')
 *       .backstory('You are a certified Salesforce CRM analyst.')
 *       .tool(queryTool)
 *       .tool(describeTool)
 *       .build();
 *
 *   FC_Agent writer = new FC_Agent.Builder('Executive Writer')
 *       .goal('Transform raw data into clear executive summaries.')
 *       .backstory('You write for C-suite audiences. Be concise and impactful.')
 *       .build();
 *
 *   // 3. Build tasks
 *   FC_Task dataTask = new FC_Task.Builder('Analyse Top Accounts')
 *       .description('Find the top 5 accounts by AnnualRevenue and list their names and revenues.')
 *       .expectedOutput('A JSON array of account names and revenues, sorted descending.')
 *       .assignToAgent('Salesforce Analyst')
 *       .build();
 *
 *   FC_Task summaryTask = new FC_Task.Builder('Write Executive Summary')
 *       .description('Summarise the top accounts into a 3-bullet briefing for the CEO.')
 *       .expectedOutput('Three concise bullet points highlighting revenue leaders.')
 *       .assignToAgent('Executive Writer')
 *       .withContext('Analyse Top Accounts')
 *       .build();
 *
 *   // 4. Assemble and run the crew
 *   FC_CrewResult result = new FC_Crew.Builder('Revenue Intelligence Crew')
 *       .agent(analyst)
 *       .agent(writer)
 *       .task(dataTask)
 *       .task(summaryTask)
 *       .verbose(true)
 *       .build()
 *       .kickoff();
 *
 *   System.debug(result.finalOutput);
 *
 * ─────────────────────────────────────────────────────────────────────────
 * Creating your own tool (FC_IMCPTool — recommended):
 *
 *   public class MyEmailTool implements FC_IMCPTool {
 *       public String getName()        { return 'SendEmail'; }
 *       public String getDescription() { return 'Sends an email to a given address.'; }
 *       public List<FC_ToolParameter> getParameters() {
 *           return new List<FC_ToolParameter>{
 *               new FC_ToolParameter.Builder('to',      FC_ToolParameter.TYPE_STRING).required().build(),
 *               new FC_ToolParameter.Builder('subject', FC_ToolParameter.TYPE_STRING).required().build(),
 *               new FC_ToolParameter.Builder('body',    FC_ToolParameter.TYPE_STRING).required().build()
 *           };
 *       }
 *       public String execute(Map<String, Object> params) {
 *           // ... Messaging.sendEmail() logic
 *           return JSON.serialize(new Map<String,Object>{'success'=>true});
 *       }
 *   }
 *
 * @group ForceCrew
 */
public class ForceCrew {

    /** Framework version. */
    public static final String VERSION = '1.0.0';

    /**
     * Returns a brief framework summary (useful for debugging / health checks).
     */
    public static String about() {
        return 'ForceCrew v' + VERSION
            + ' — crewAI-inspired multi-agent framework for Salesforce Apex. '
            + 'Powered by the Salesforce Models API.';
    }

    /**
     * Convenience method: builds and runs a single-agent crew on a single task.
     * Useful for simple, one-shot AI invocations without full crew setup.
     *
     * @param agentRole  The agent's role label
     * @param goal       The agent's goal
     * @param backstory  The agent's backstory
     * @param tools      Tools to give the agent (may be null or empty)
     * @param taskDesc   Description of what the agent should do
     * @param expected   Expected output specification
     * @return The agent's final answer string, or an error message
     */
    public static String runAgent(
        String         agentRole,
        String         goal,
        String         backstory,
        List<FC_Tool>  tools,
        String         taskDesc,
        String         expected
    ) {
        FC_Agent.Builder agentBuilder = new FC_Agent.Builder(agentRole)
            .goal(goal)
            .backstory(backstory);

        if (tools != null) {
            for (FC_Tool t : tools) {
                agentBuilder.tool(t);
            }
        }

        FC_Task task = new FC_Task.Builder('Task')
            .description(taskDesc)
            .expectedOutput(expected)
            .assignToAgent(agentRole)
            .build();

        FC_CrewResult result = new FC_Crew.Builder('Single-Agent Crew')
            .agent(agentBuilder.build())
            .task(task)
            .build()
            .kickoff();

        return result.success ? result.finalOutput : ('Error: ' + result.errorMessage);
    }
}
