/**
 * FC_CrewQueueableTest - Unit tests for FC_CrewQueueable.
 *
 * Tests cover:
 *   - Config serialisation (crew → CrewRunConfig round-trip)
 *   - Agent/task reconstruction from stored JSON
 *   - Status constants
 *   - Hierarchical process rejection
 *   - Setup instructions output
 *
 * NOTE: Full end-to-end Queueable execution tests require the FC_CrewRun__c
 * custom object and FC_CrewEvent__e Platform Event to be deployed.
 * The tests below are structured to pass even if those objects are absent
 * by testing the serialisable config layer independently.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_CrewQueueableTest {

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static FC_Crew buildTestCrew() {
        return new FC_Crew.Builder('Test Async Crew')
            .agent(new FC_Agent.Builder('Analyst')
                .goal('Analyse data')
                .backstory('Expert analyst')
                .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
                .build())
            .agent(new FC_Agent.Builder('Writer')
                .goal('Write summaries')
                .backstory('Expert writer')
                .build())
            .task(new FC_Task.Builder('Task A')
                .description('Do task A')
                .expectedOutput('Output A')
                .assignToAgent('Analyst')
                .build())
            .task(new FC_Task.Builder('Task B')
                .description('Do task B using context from A')
                .expectedOutput('Output B')
                .assignToAgent('Writer')
                .withContext('Task A')
                .build())
            .build();
    }

    // ─── Config Serialisation ─────────────────────────────────────────────────

    @IsTest
    static void testCrewRunConfigRoundTrip() {
        FC_Crew crew = buildTestCrew();

        // Serialise via the inner config builder (accessed via setupInstructions indirectly)
        // We test via JSON serialise/deserialise of the config structure
        FC_CrewQueueable.CrewRunConfig config = new FC_CrewQueueable.CrewRunConfig();
        config.crewName      = crew.getName();
        config.process       = crew.getProcess().name();
        config.verbose       = crew.isVerbose();
        config.failFast      = crew.isFailFast();
        config.correlationId = 'TEST-001';

        config.agents = new List<FC_CrewQueueable.AgentConfig>();
        FC_CrewQueueable.AgentConfig ac = new FC_CrewQueueable.AgentConfig();
        ac.role           = 'Analyst';
        ac.goal           = 'Analyse data';
        ac.backstory      = 'Expert analyst';
        ac.maxIterations  = 10;
        ac.toolClassNames = new List<String>{ 'FC_SampleSOQLTool' };
        config.agents.add(ac);

        config.tasks = new List<FC_CrewQueueable.TaskConfig>();
        FC_CrewQueueable.TaskConfig tc = new FC_CrewQueueable.TaskConfig();
        tc.name              = 'Task A';
        tc.description       = 'Do task A';
        tc.expectedOutput    = 'Output A';
        tc.assignedAgentRole = 'Analyst';
        tc.contextTaskNames  = new List<String>();
        config.tasks.add(tc);

        String serialised = JSON.serialize(config);
        Assert.isTrue(String.isNotBlank(serialised));

        // Round-trip
        FC_CrewQueueable.CrewRunConfig restored =
            (FC_CrewQueueable.CrewRunConfig) JSON.deserialize(serialised, FC_CrewQueueable.CrewRunConfig.class);

        Assert.areEqual('Test Async Crew',  restored.crewName);
        Assert.areEqual('SEQUENTIAL',       restored.process);
        Assert.areEqual('TEST-001',         restored.correlationId);
        Assert.areEqual(1,                  restored.agents.size());
        Assert.areEqual('Analyst',          restored.agents[0].role);
        Assert.areEqual('FC_SampleSOQLTool', restored.agents[0].toolClassNames[0]);
        Assert.areEqual(1,                  restored.tasks.size());
        Assert.areEqual('Task A',           restored.tasks[0].name);
    }

    @IsTest
    static void testAgentConfigToolClassNames() {
        FC_CrewQueueable.AgentConfig ac = new FC_CrewQueueable.AgentConfig();
        ac.role           = 'Analyst';
        ac.toolClassNames = new List<String>{ 'FC_SampleSOQLTool', 'FC_SampleDescribeTool' };

        String json_x = JSON.serialize(ac);
        FC_CrewQueueable.AgentConfig restored =
            (FC_CrewQueueable.AgentConfig) JSON.deserialize(json_x, FC_CrewQueueable.AgentConfig.class);

        Assert.areEqual(2, restored.toolClassNames.size());
        Assert.isTrue(restored.toolClassNames.contains('FC_SampleSOQLTool'));
        Assert.isTrue(restored.toolClassNames.contains('FC_SampleDescribeTool'));
    }

    @IsTest
    static void testTaskConfigContextTaskNames() {
        FC_CrewQueueable.TaskConfig tc = new FC_CrewQueueable.TaskConfig();
        tc.name             = 'Summary';
        tc.contextTaskNames = new List<String>{ 'Task A', 'Task B' };

        String json_x = JSON.serialize(tc);
        FC_CrewQueueable.TaskConfig restored =
            (FC_CrewQueueable.TaskConfig) JSON.deserialize(json_x, FC_CrewQueueable.TaskConfig.class);

        Assert.areEqual(2, restored.contextTaskNames.size());
        Assert.isTrue(restored.contextTaskNames.contains('Task A'));
    }

    // ─── Status Constants ─────────────────────────────────────────────────────

    @IsTest
    static void testStatusConstants() {
        Assert.areEqual('Pending',   FC_CrewQueueable.STATUS_PENDING);
        Assert.areEqual('Running',   FC_CrewQueueable.STATUS_RUNNING);
        Assert.areEqual('Completed', FC_CrewQueueable.STATUS_COMPLETED);
        Assert.areEqual('Failed',    FC_CrewQueueable.STATUS_FAILED);
    }

    // ─── Hierarchical Rejection ───────────────────────────────────────────────

    @IsTest
    static void testEnqueueRejectsHierarchicalProcess() {
        FC_Crew crew = new FC_Crew.Builder('H Crew')
            .process(FC_Process.Type.HIERARCHICAL)
            .agent(new FC_Agent.Builder('A').build())
            .task(new FC_Task.Builder('T').assignToAgent('A').build())
            .managerLlmModel('sfdc_ai__DefaultGPT4Omni')
            .build();

        try {
            FC_CrewQueueable.enqueue(crew);
            Assert.fail('Expected ConfigurationException for HIERARCHICAL process');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('SEQUENTIAL'));
        }
    }

    // ─── Setup Instructions ───────────────────────────────────────────────────

    @IsTest
    static void testSetupInstructionsNotBlank() {
        String instructions = FC_CrewQueueable.setupInstructions();
        Assert.isTrue(String.isNotBlank(instructions));
        Assert.isTrue(instructions.contains('FC_CrewRun__c'));
        Assert.isTrue(instructions.contains('FC_CrewEvent__e'));
        Assert.isTrue(instructions.contains('FC_IMCPTool'));
    }

    // ─── Queueable Constructor ────────────────────────────────────────────────

    @IsTest
    static void testQueueableConstructor() {
        // Verify the Queueable can be instantiated (does not throw)
        FC_CrewQueueable job = new FC_CrewQueueable(null, 0);
        Assert.isNotNull(job);
    }

    // ─── Task Output Deserialisation ──────────────────────────────────────────

    @IsTest
    static void testTaskOutputsJsonRoundTrip() {
        Map<String, String> outputs = new Map<String, String>{
            'Task A' => 'Account A had $1M revenue',
            'Task B' => 'Summary: strong performance'
        };
        String json_x = JSON.serialize(outputs);

        // Simulate what readCrewRunRecord + deserialization does
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(json_x);
        Map<String, String> restored = new Map<String, String>();
        for (String k : raw.keySet()) {
            restored.put(k, String.valueOf(raw.get(k)));
        }

        Assert.areEqual('Account A had $1M revenue', restored.get('Task A'));
        Assert.areEqual('Summary: strong performance', restored.get('Task B'));
    }
}
