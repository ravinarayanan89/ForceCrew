/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_AgentTest {

    @IsTest
    static void testBuilderDefaults() {
        FC_Agent agent = new FC_Agent.Builder('Researcher').build();

        Assert.areEqual('Researcher', agent.role);
        Assert.isTrue(String.isNotBlank(agent.goal));
        Assert.isTrue(String.isNotBlank(agent.backstory));
        Assert.areEqual(10, agent.maxIterations);
        Assert.isFalse(agent.verbose);
        Assert.isFalse(agent.allowDelegation);
        Assert.isTrue(agent.tools.isEmpty());
        Assert.isNull(agent.llmModel);
    }

    @IsTest
    static void testBuilderFullConfig() {
        FC_Agent agent = new FC_Agent.Builder('Analyst')
            .goal('Analyse data')
            .backstory('Expert analyst')
            .maxIterations(5)
            .verbose(true)
            .allowDelegation(true)
            .llmModel('sfdc_ai__DefaultGPT4OmniMini')
            .build();

        Assert.areEqual('Analyse data',                    agent.goal);
        Assert.areEqual('Expert analyst',                  agent.backstory);
        Assert.areEqual(5,                                 agent.maxIterations);
        Assert.isTrue(agent.verbose);
        Assert.isTrue(agent.allowDelegation);
        Assert.areEqual('sfdc_ai__DefaultGPT4OmniMini',   agent.llmModel);
    }

    @IsTest
    static void testBlankRoleThrows() {
        try {
            new FC_Agent.Builder('').build();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('role'));
        }
    }

    @IsTest
    static void testAddSingleTool() {
        FC_Agent agent = new FC_Agent.Builder('Agent')
            .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
            .build();

        Assert.isTrue(agent.hasTools());
        Assert.areEqual(1, agent.tools.size());
    }

    @IsTest
    static void testAddMultipleTools() {
        List<FC_Tool> tools = new List<FC_Tool>{
            FC_Tool.fromMCP(new FC_SampleSOQLTool()),
            FC_Tool.fromMCP(new FC_SampleDescribeTool())
        };
        FC_Agent agent = new FC_Agent.Builder('Agent').tools(tools).build();

        Assert.areEqual(2, agent.tools.size());
    }

    @IsTest
    static void testNullToolIgnored() {
        FC_Agent agent = new FC_Agent.Builder('Agent').tool(null).build();
        Assert.isFalse(agent.hasTools());
    }

    @IsTest
    static void testGetToolFound() {
        FC_Agent agent = new FC_Agent.Builder('Agent')
            .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
            .build();

        Assert.isNotNull(agent.getTool('QueryRecords'));
    }

    @IsTest
    static void testGetToolNotFound() {
        FC_Agent agent = new FC_Agent.Builder('Agent').build();
        Assert.isNull(agent.getTool('NonExistent'));
    }

    @IsTest
    static void testSystemPromptContainsRoleAndGoal() {
        FC_Agent agent = new FC_Agent.Builder('Data Scientist')
            .goal('Analyse Salesforce metrics')
            .backstory('Expert in CRM analytics')
            .build();

        String prompt = agent.buildSystemPrompt();
        Assert.isTrue(prompt.contains('Data Scientist'));
        Assert.isTrue(prompt.contains('Analyse Salesforce metrics'));
        Assert.isTrue(prompt.contains('Expert in CRM analytics'));
        Assert.isTrue(prompt.contains('FINAL_ANSWER'));
    }

    @IsTest
    static void testSystemPromptWithToolsContainsToolSection() {
        FC_Agent agent = new FC_Agent.Builder('Agent')
            .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
            .build();

        String prompt = agent.buildSystemPrompt();
        Assert.isTrue(prompt.contains('QueryRecords'));
        Assert.isTrue(prompt.contains('TOOL_CALL'));
        Assert.isTrue(prompt.contains('FINAL_ANSWER'));
        Assert.isTrue(prompt.contains('Available Tools'));
    }

    @IsTest
    static void testSystemPromptWithoutToolsNoToolSection() {
        FC_Agent agent = new FC_Agent.Builder('Agent').build();
        String prompt = agent.buildSystemPrompt();
        Assert.isFalse(prompt.contains('TOOL_CALL'));
        Assert.isTrue(prompt.contains('FINAL_ANSWER'));
    }

    @IsTest
    static void testMaxIterationsClamped() {
        FC_Agent agent = new FC_Agent.Builder('Agent').maxIterations(-1).build();
        Assert.areEqual(10, agent.maxIterations);
    }
}
