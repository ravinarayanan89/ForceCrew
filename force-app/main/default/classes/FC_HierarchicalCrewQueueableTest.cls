/**
 * FC_HierarchicalCrewQueueableTest - Unit tests for FC_HierarchicalCrewQueueable.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_HierarchicalCrewQueueableTest {

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private class MockQueueableContext implements QueueableContext {
        public Id getJobId() {
            return (Id) '707gK000000001A';
        }
    }

    private static FC_Crew buildSimpleHierarchicalCrew(String crewName) {
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
            .process(FC_Process.Type.HIERARCHICAL)
            .agent(analyst)
            .task(taskA)
            .managerLlmModel(FC_ModelsAPIService.MODEL_GPT4O_MINI)
            .build();
    }

    private static FC_CrewQueueable.CrewRunConfig buildConfigForRun(FC_Crew crew, String correlationId) {
        return (FC_CrewQueueable.CrewRunConfig) FC_CrewQueueable.buildCrewRunConfig(crew, correlationId);
    }

    private static Id createCrewRunRecord(FC_CrewQueueable.CrewRunConfig config, Map<String, String> taskOutputs) {
        FC_CrewRun__c run = new FC_CrewRun__c();
        run.CrewName__c        = config.crewName;
        run.Status__c           = FC_CrewQueueable.STATUS_PENDING;
        run.CrewConfigJson__c   = JSON.serialize(config);
        run.TaskOutputsJson__c  = JSON.serialize(taskOutputs);
        run.CorrelationId__c    = config.correlationId;
        insert run;
        return run.Id;
    }

    // ─── enqueue() ────────────────────────────────────────────────────────────

    @IsTest
    static void testEnqueueRejectsSequentialCrew() {
        FC_Crew crew = new FC_Crew.Builder('Seq Crew')
            .agent(new FC_Agent.Builder('Analyst').build())
            .task(new FC_Task.Builder('Task A').assignToAgent('Analyst').build())
            .build();

        try {
            FC_HierarchicalCrewQueueable.enqueue(crew);
            Assert.fail('Expected ConfigurationException for a SEQUENTIAL crew');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('HIERARCHICAL'));
        }
    }

    @IsTest
    static void testEnqueueCreatesPendingRunRecord() {
        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical Enqueue');

        // Deliberately not wrapped in Test.startTest()/stopTest() — we only want to
        // verify record creation here, not let the enqueued job actually run.
        Id runId = FC_HierarchicalCrewQueueable.enqueue(crew, new Map<String, Object>{ 'seed' => 'value' }, 'CORR-ENQUEUE');

        FC_CrewRun__c run = [
            SELECT Status__c, CrewName__c, CorrelationId__c, CrewConfigJson__c, TaskOutputsJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_PENDING, run.Status__c);
        Assert.areEqual('Hierarchical Enqueue', run.CrewName__c);
        Assert.areEqual('CORR-ENQUEUE', run.CorrelationId__c);

        Map<String, Object> outputs = (Map<String, Object>) JSON.deserializeUntyped(run.TaskOutputsJson__c);
        Assert.areEqual('value', String.valueOf(outputs.get('seed')));
    }

    @IsTest
    static void testDelegateThenFinalAnswerCompletesAcrossRounds() {
        FC_ModelsAPIService.clearMocks();
        // Round 0: manager delegates "Task A" to "Analyst".
        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"Analyst"}'
        );
        // The delegated agent's own ReAct loop (one iteration, immediate FINAL_ANSWER).
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Task A done"}'
        );
        // Round 1: manager concludes.
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"All done"}'
        );

        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical Success');
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-HIER-OK');
        Id runId = createCrewRunRecord(config, new Map<String, String>{ 'seed' => 'value' });

        // Apex test context does not support more than one hop of Queueable chaining
        // (Test.stopTest() running job[0], which itself chains to job[1], throws
        // "Maximum stack depth has been reached"). Drive each round by hand instead —
        // this still exercises the exact same execute() logic as production, just
        // without relying on the platform to auto-run the chain.
        new FC_HierarchicalCrewQueueable(runId, 0).execute(new MockQueueableContext());

        FC_CrewRun__c afterRound0 = [
            SELECT Status__c, TaskOutputsJson__c, ManagerHistoryJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_RUNNING, afterRound0.Status__c);
        Assert.isNotNull(afterRound0.ManagerHistoryJson__c);
        Map<String, Object> outputsAfterRound0 =
            (Map<String, Object>) JSON.deserializeUntyped(afterRound0.TaskOutputsJson__c);
        Assert.areEqual('Task A done', String.valueOf(outputsAfterRound0.get('Task A')));

        new FC_HierarchicalCrewQueueable(runId, 1).execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, FinalOutput__c, ErrorMessage__c, TaskOutputsJson__c, ManagerHistoryJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_COMPLETED, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.areEqual('All done', run.FinalOutput__c);

        Map<String, Object> outputs = (Map<String, Object>) JSON.deserializeUntyped(run.TaskOutputsJson__c);
        Assert.areEqual('Task A done', String.valueOf(outputs.get('Task A')));
    }

    // ─── execute() — single-round behaviour ───────────────────────────────────

    @IsTest
    static void testExecuteInvalidDirectiveJsonAdvancesRound() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock('not valid json at all');

        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical Bad JSON');
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-BAD-JSON');
        Id runId = createCrewRunRecord(config, new Map<String, String>());

        FC_HierarchicalCrewQueueable job = new FC_HierarchicalCrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, ErrorMessage__c, ManagerHistoryJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_RUNNING, run.Status__c);
        Assert.isNull(run.ErrorMessage__c);
        Assert.isTrue(run.ManagerHistoryJson__c.contains('not valid JSON'));
    }

    @IsTest
    static void testExecuteManagerLlmFailureFinalisesFailed() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('Manager LLM boom');

        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical LLM Failure');
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-LLM-FAIL');
        Id runId = createCrewRunRecord(config, new Map<String, String>());

        FC_HierarchicalCrewQueueable job = new FC_HierarchicalCrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, ErrorMessage__c, FinalOutput__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_FAILED, run.Status__c);
        Assert.isNull(run.FinalOutput__c);
        Assert.isTrue(run.ErrorMessage__c.contains('Manager LLM error'));
    }

    @IsTest
    static void testExecuteMaxRoundsExceededFinalisesFailed() {
        FC_ModelsAPIService.clearMocks();
        // No mocks needed — the round cap is checked before any LLM call.

        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical Round Overrun');
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-ROUNDS');
        Id runId = createCrewRunRecord(config, new Map<String, String>());

        FC_HierarchicalCrewQueueable job = new FC_HierarchicalCrewQueueable(runId, 20);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_FAILED, run.Status__c);
        Assert.isTrue(run.ErrorMessage__c.contains('exceeded max rounds'));
    }

    @IsTest
    static void testExecuteDelegateUnknownTaskAddsErrorAndAdvances() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Nonexistent Task","agent":"Analyst"}'
        );

        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical Unknown Task');
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-UNKNOWN-TASK');
        Id runId = createCrewRunRecord(config, new Map<String, String>());

        FC_HierarchicalCrewQueueable job = new FC_HierarchicalCrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, ManagerHistoryJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        Assert.areEqual(FC_CrewQueueable.STATUS_RUNNING, run.Status__c);
        Assert.isTrue(run.ManagerHistoryJson__c.contains('not found'));
        Assert.isTrue(run.ManagerHistoryJson__c.contains('Available tasks'));
    }

    @IsTest
    static void testExecuteDelegateToolLoadFailureRecordsFailureAndAdvances() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"Analyst"}'
        );

        FC_Crew crew = buildSimpleHierarchicalCrew('Hierarchical Tool Load Failure');
        FC_CrewQueueable.CrewRunConfig config = buildConfigForRun(crew, 'CORR-TOOL-FAIL');
        config.agents[0].toolClassNames = new List<String>{ 'NonExistentClassName_XYZ' };
        Id runId = createCrewRunRecord(config, new Map<String, String>());

        FC_HierarchicalCrewQueueable job = new FC_HierarchicalCrewQueueable(runId, 0);
        job.execute(new MockQueueableContext());

        FC_CrewRun__c run = [
            SELECT Status__c, ManagerHistoryJson__c, TaskOutputsJson__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];
        // A tool that fails to load reports back to the manager rather than hard-failing
        // the whole crew — the manager can re-delegate elsewhere.
        Assert.areEqual(FC_CrewQueueable.STATUS_RUNNING, run.Status__c);
        Assert.isTrue(run.ManagerHistoryJson__c.contains('could not be built'));
        Assert.isTrue(run.ManagerHistoryJson__c.contains('NonExistentClassName_XYZ'));

        Map<String, Object> outputs = (Map<String, Object>) JSON.deserializeUntyped(run.TaskOutputsJson__c);
        Assert.isFalse(outputs.containsKey('Task A'));
    }

    @IsTest
    static void testExecuteRunNotFoundReturnsWithoutThrow() {
        Id nonExistent = Id.valueOf('001000000000000AAA');
        FC_HierarchicalCrewQueueable job = new FC_HierarchicalCrewQueueable(nonExistent, 0);

        Test.startTest();
        job.execute(new MockQueueableContext());
        Test.stopTest();

        Assert.isTrue(true);
    }

    // ─── History (de)serialisation ────────────────────────────────────────────

    @IsTest
    static void testDeserialiseHistoryHandlesBlankAndRoundTrip() {
        List<FC_ChatMessage> empty = (List<FC_ChatMessage>) FC_HierarchicalCrewQueueable.deserialiseHistory(null);
        Assert.areEqual(0, empty.size());

        String json_x = '[{"role":"system","content":"You are the manager."},'
            + '{"role":"user","content":"Coordinate the crew."}]';
        List<FC_ChatMessage> restored = (List<FC_ChatMessage>) FC_HierarchicalCrewQueueable.deserialiseHistory(json_x);
        Assert.areEqual(2, restored.size());
        Assert.areEqual('system', restored[0].role);
        Assert.areEqual('You are the manager.', restored[0].content);
        Assert.areEqual('user', restored[1].role);
    }
}
