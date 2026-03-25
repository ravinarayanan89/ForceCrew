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

    // ─────────────────────────────────────────────────────────────────────────
    // Additional coverage: execute(), helpers, and status transitions
    // ─────────────────────────────────────────────────────────────────────────

    private class MockQueueableContext implements QueueableContext {
        // AsyncApexJob prefix is 707; must be a valid 15-char Salesforce Id
        public Id getJobId() {
            return (Id) '707gK000000001A';
        }
    }

    private static FC_CrewQueueable.CrewRunConfig buildConfigForRun(FC_Crew crew, String correlationId) {
        return (FC_CrewQueueable.CrewRunConfig) FC_CrewQueueable.buildCrewRunConfig(crew, correlationId);
    }

    private static Id createCrewRunRecord(FC_CrewQueueable.CrewRunConfig config, Map<String, String> taskOutputs) {
        FC_CrewRun__c run = new FC_CrewRun__c();
        run.CrewName__c = config.crewName;
        run.Status__c = FC_CrewQueueable.STATUS_PENDING;
        run.CrewConfigJson__c = JSON.serialize(config);
        run.TaskOutputsJson__c = JSON.serialize(taskOutputs);
        run.CorrelationId__c = config.correlationId;
        insert run;
        return run.Id;
    }

    private static FC_Crew buildSimpleCrew(String crewName, Boolean verbose, Boolean failFast) {
        FC_Agent analyst = new FC_Agent.Builder('Analyst')
            .goal('Analyse data')
            .backstory('Expert analyst')
            .llmModel(FC_ModelsAPIService.MODEL_GPT4O_MINI)
            .build();

        FC_Task taskA = new FC_Task.Builder('Task A')
            .description('Do task A')
            .expectedOutput('Output A')
            .assignToAgent('Analyst')
            .build();

        return new FC_Crew.Builder(crewName)
            .verbose(verbose)
            .failFast(failFast)
            .agent(analyst)
            .task(taskA)
            .build();
    }

    @IsTest
    static void testExecuteSuccessFinalisesCompleted() {
        FC_ModelsAPIService.clearMocks();
        // The agent executor will run one iteration and immediately return FINAL_ANSWER.
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Crew Completed"}'
        );

        FC_Crew crew = buildSimpleCrew('Crew Success', true, true);

        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-SUCCESS');
        // Cover buildAgent tool loading success + failure:
        // - valid tool class should be instantiated
        // - invalid class should be caught/logged without throwing
        config.agents[0].toolClassNames = new List<String>{ 'FC_SampleSOQLTool', 'NonExistentClassName_XYZ', '' };

        Map<String, String> initialOutputs = new Map<String, String>{ 'Task A' => 'seed value' };
        Id runId = createCrewRunRecord(config, initialOutputs);

        FC_CrewQueueable job = new FC_CrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c, TaskOutputsJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];

        Assert.areEqual(FC_CrewQueueable.STATUS_COMPLETED, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.areEqual('Crew Completed', run.FinalOutput__c);

        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(run.TaskOutputsJson__c);
        Assert.areEqual('Crew Completed', String.valueOf(raw.get('Task A')));
    }

    @IsTest
    static void testExecuteMissingAgentRoleFailFastSetsFailed() {
        FC_Crew crew = buildSimpleCrew('Crew Missing Agent', false, true);

        // Build config and intentionally make the task reference a non-existent agent role.
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-MISSING-AGENT');
        config.tasks[0].assignedAgentRole = 'UnknownRole';

        Map<String, String> initialOutputs = new Map<String, String>{ 'Task A' => 'seed value' };
        Id runId = createCrewRunRecord(config, initialOutputs);

        FC_CrewQueueable job = new FC_CrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_FAILED, run.Status__c);
        Assert.isNotNull(run.ErrorMessage__c);
        Assert.isNull(run.FinalOutput__c);
        Assert.isTrue(run.ErrorMessage__c.contains('No agent with role'));
    }

    @IsTest
    static void testExecuteLLMFailureFailFastFalseStillFinalisesCompleted() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('LLM boom');

        FC_Crew crew = buildSimpleCrew('Crew LLM Failure', false, false);

        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-LLM-FAIL');
        // Keep tool list empty so the failure path is purely LLM-driven.
        config.agents[0].toolClassNames = new List<String>();

        Map<String, String> initialOutputs = new Map<String, String>{ 'Task A' => 'seed value' };
        Id runId = createCrewRunRecord(config, initialOutputs);

        FC_CrewQueueable job = new FC_CrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];

        // Current implementation finalises the crew as COMPLETED even when the task fails
        // and failFast=false. This test locks in that behaviour for coverage.
        Assert.areEqual(FC_CrewQueueable.STATUS_COMPLETED, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.areEqual('seed value', run.FinalOutput__c);
    }

    @IsTest
    static void testExecuteTaskIndexBeyondSizeFinalisesCompletedWithNullFinalOutput() {
        FC_ModelsAPIService.clearMocks();
        // No LLM mocks needed — the job should finalise before executing any task.

        FC_Crew crew = buildSimpleCrew('Crew Index Overrun', false, true);
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-OVERRUN');

        // Seed with blank output so finalOutput remains null.
        Map<String, String> initialOutputs = new Map<String, String>{ 'Task A' => '' };
        Id runId = createCrewRunRecord(config, initialOutputs);

        // Create a job at taskIndex == tasks.size() so it takes the defensive finalise branch.
        FC_CrewQueueable job = new FC_CrewQueueable(runId, config.tasks.size());
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_COMPLETED, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.isNull(run.FinalOutput__c);
    }

    @IsTest
    static void testExecuteRunNotFoundReturnsWithoutThrow() {
        // If the record doesn't exist, execute() returns early.
        // Use a dummy Id of the correct shape.
        Id nonExistent = Id.valueOf('001000000000000AAA');
        FC_CrewQueueable job = new FC_CrewQueueable(nonExistent, 0);

        Test.startTest();
        job.execute(new MockQueueableContext());
        Test.stopTest();

        Assert.isTrue(true);
    }

    @IsTest
    static void testBuildAgentToolClassNamesSuccessAndFailure() {
        FC_CrewQueueable.AgentConfig cfg = new FC_CrewQueueable.AgentConfig();
        cfg.role = 'Analyst';
        cfg.goal = 'Analyse data';
        cfg.backstory = 'Expert analyst';
        cfg.maxIterations = 1;
        cfg.llmModel = FC_ModelsAPIService.MODEL_GPT4O_MINI;
        cfg.toolClassNames = new List<String>{ 'FC_SampleSOQLTool', 'NonExistentClassName_XYZ', '' };

        FC_Agent agent = (FC_Agent) FC_CrewQueueable.buildAgent(cfg);
        Assert.isNotNull(agent);
        Assert.isNotNull(agent.getTool('QueryRecords'));
    }

    @IsTest
    static void testBuildTaskNullContextDoesNotThrow() {
        FC_CrewQueueable.TaskConfig tc = new FC_CrewQueueable.TaskConfig();
        tc.name = 'Task X';
        tc.description = 'desc';
        tc.expectedOutput = 'expected';
        tc.assignedAgentRole = 'Analyst';
        tc.contextTaskNames = null;

        FC_Task task = (FC_Task) FC_CrewQueueable.buildTask(tc);
        Assert.areEqual('Task X', task.name);
    }

    @IsTest
    static void testResolveAgentBlankRoleAndEmptyAgents() {
        FC_CrewQueueable.AgentConfig a1 = new FC_CrewQueueable.AgentConfig();
        a1.role = 'Analyst';

        List<FC_CrewQueueable.AgentConfig> agents = new List<FC_CrewQueueable.AgentConfig>{ a1 };
        FC_CrewQueueable.AgentConfig resolved = (FC_CrewQueueable.AgentConfig) FC_CrewQueueable.resolveAgent(agents, '');
        Assert.areEqual('Analyst', resolved.role);

        List<FC_CrewQueueable.AgentConfig> none = new List<FC_CrewQueueable.AgentConfig>();
        resolved = (FC_CrewQueueable.AgentConfig) FC_CrewQueueable.resolveAgent(none, '');
        Assert.isNull(resolved);
    }

    @IsTest
    static void testDeserialiseTaskOutputsInvalidJsonReturnsEmptyMap() {
        Map<String, String> restored = (Map<String, String>) FC_CrewQueueable.deserialiseTaskOutputs('not valid json');
        Assert.isNotNull(restored);
        Assert.areEqual(0, restored.size());

        restored = (Map<String, String>) FC_CrewQueueable.deserialiseTaskOutputs('');
        Assert.areEqual(0, restored.size());
    }

    @IsTest
    static void testEnqueueSeedsInputsAndExecutesQueueable() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"FinalFromLLM"}'
        );

        FC_Crew crew = buildSimpleCrew('Crew Enqueue', false, true);

        // Seed inputs (covers null-handling + String.valueOf() conversion in enqueue()).
        Map<String, Object> inputs = new Map<String, Object>{
            'Task A' => 'SeedFromInputs',
            'SomeNumber' => 123,
            'NullVal' => null
        };

        Test.startTest();
        Id runId = FC_CrewQueueable.enqueue(crew, inputs, 'CORR-ENQUEUE');
        Test.stopTest();

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c, CorrelationId__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_COMPLETED, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.areEqual('FinalFromLLM', run.FinalOutput__c);
        Assert.areEqual('CORR-ENQUEUE', run.CorrelationId__c);
    }

    @IsTest
    static void testExecuteLLMFailureFailFastTrueFinalisesFailed() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('LLM boom');

        FC_Crew crew = buildSimpleCrew('Crew LLM Failure FailFast', false, true);
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-LLM-FAIL-FF');
        config.agents[0].toolClassNames = new List<String>();

        Map<String, String> initialOutputs = new Map<String, String>{ 'Task A' => 'seed value' };
        Id runId = createCrewRunRecord(config, initialOutputs);

        FC_CrewQueueable job = new FC_CrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];

        Assert.areEqual(FC_CrewQueueable.STATUS_FAILED, run.Status__c);
        Assert.isNotNull(run.ErrorMessage__c);
        Assert.isNull(run.FinalOutput__c);
        Assert.isTrue(run.ErrorMessage__c.contains('Task "Task A" failed'));
    }

    @IsTest
    static void testBuildAgentSkipsNullLlmModelAndToolClassNames() {
        FC_CrewQueueable.AgentConfig cfg = new FC_CrewQueueable.AgentConfig();
        cfg.role = 'Analyst';
        cfg.goal = 'Analyse data';
        cfg.backstory = 'Expert analyst';
        cfg.maxIterations = 1;
        cfg.llmModel = null;
        cfg.toolClassNames = null;

        FC_Agent agent = (FC_Agent) FC_CrewQueueable.buildAgent(cfg);
        Assert.isNotNull(agent);
        Assert.areEqual(0, agent.tools.size());
    }

    @IsTest
    static void testExecuteMissingAgentRoleFailFastFalseFinalisesCompleted() {
        FC_Crew crew = buildSimpleCrew('Crew Missing Agent FailFastFalse', false, false);

        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-MISSING-AGENT-FF');
        config.tasks[0].assignedAgentRole = 'UnknownRole';

        Map<String, String> initialOutputs = new Map<String, String>{ 'Task A' => 'seed value' };
        Id runId = createCrewRunRecord(config, initialOutputs);

        FC_CrewQueueable job = new FC_CrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_COMPLETED, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.areEqual('seed value', run.FinalOutput__c);
    }

    @IsTest
    static void testExecuteEnqueuesNextJobForMultipleTasks() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Output A"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Output B"}'
        );

        FC_Agent analyst = new FC_Agent.Builder('Analyst')
            .goal('Analyse data')
            .backstory('Expert analyst')
            .llmModel(FC_ModelsAPIService.MODEL_GPT4O_MINI)
            .build();

        FC_Task taskA = new FC_Task.Builder('Task A')
            .description('Do task A')
            .expectedOutput('Output A')
            .assignToAgent('Analyst')
            .build();

        FC_Task taskB = new FC_Task.Builder('Task B')
            .description('Do task B')
            .expectedOutput('Output B')
            .assignToAgent('Analyst')
            .build();

        FC_Crew crew = new FC_Crew.Builder('Crew Chain')
            .verbose(false)
            .failFast(true)
            .agent(analyst)
            .task(taskA)
            .task(taskB)
            .build();

        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-CHAIN');
        config.agents[0].toolClassNames = new List<String>();

        Map<String, String> initialOutputs = new Map<String, String>{
            'Task A' => '',
            'Task B' => ''
        };
        Id runId = createCrewRunRecord(config, initialOutputs);

        FC_CrewQueueable job = new FC_CrewQueueable(runId, 0);

        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, TaskOutputsJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        // Since the next queueable is only enqueued (not executed here),
        // we should remain in Running state and only persist task A output.
        Assert.areEqual(FC_CrewQueueable.STATUS_RUNNING, run.Status__c);
        Assert.isNull(run.FinalOutput__c);

        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(run.TaskOutputsJson__c);
        Assert.areEqual('Output A', String.valueOf(raw.get('Task A')));
        Assert.isTrue(String.isBlank(String.valueOf(raw.get('Task B'))));
    }
}
