/**
 * FC_ManagerAgentTest - Unit tests for FC_ManagerAgent.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_ManagerAgentTest {

    private static FC_Agent buildAgent(String role, Integer maxIterations) {
        return new FC_Agent.Builder(role)
            .goal('Agent goal')
            .backstory('Agent backstory')
            .maxIterations(maxIterations)
            .build();
    }

    private static FC_Agent buildToolAgent(String role, Integer maxIterations) {
        return new FC_Agent.Builder(role)
            .goal('Agent goal with tools')
            .backstory('Agent backstory')
            .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
            .maxIterations(maxIterations)
            .build();
    }

    private static FC_Task buildTask(String name, String assignedRole) {
        return new FC_Task.Builder(name)
            .description('Do ' + name)
            .expectedOutput('Output ' + name)
            .assignToAgent(assignedRole)
            .build();
    }

    private static FC_Crew buildHierarchicalCrew(
        String crewName, List<FC_Agent> agents, List<FC_Task> tasks
    ) {
        FC_Crew.Builder b = new FC_Crew.Builder(crewName)
            .process(FC_Process.Type.HIERARCHICAL)
            .managerLlmModel(FC_ModelsAPIService.MODEL_GPT4O_MINI)
            .verbose(false)
            .failFast(true);
        for (FC_Agent a : agents) b.agent(a);
        for (FC_Task t : tasks)   b.task(t);
        return b.build();
    }

    // ─── 1. Basic delegate + FINAL_ANSWER (with instruction → buildOverrideTask) ─

    @IsTest
    static void testHierarchicalDelegateThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();

        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"Analyst","instruction":"Do delegated work"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Delegated Done"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"All done"}'
        );

        FC_Crew crew = buildHierarchicalCrew('Crew Delegate',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isTrue(result.success);
        Assert.areEqual('Delegated Done', result.finalOutput);
        Assert.areEqual(1, result.taskResults.size());
        Assert.isTrue(result.taskResults[0].success);
    }

    // ─── 2. Inputs seeding + agent WITH tools (covers lines 33-35, 142-144, 170-172) ─

    @IsTest
    static void testHierarchicalWithInputsAndTooledAgent() {
        FC_ModelsAPIService.clearMocks();

        // Manager sees non-empty inputs in its initial prompt
        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"Analyst"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Tool Agent Done"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"Done with inputs"}'
        );

        // buildToolAgent ensures the [Tools: ...] branch in buildManagerSystemPrompt runs
        FC_Crew crew = buildHierarchicalCrew('Crew With Inputs',
            new List<FC_Agent>{ buildToolAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        // Non-null inputs → seeding loop (lines 33-35) + initial prompt (lines 170-172)
        FC_CrewResult result = crew.kickoff(
            new Map<String, Object>{ 'accountId' => '001000000000001' }
        );

        Assert.isTrue(result.success);
        Assert.areEqual('Tool Agent Done', result.finalOutput);
    }

    // ─── 3. Manager LLM failure → crew fails (covers line 47) ────────────────

    @IsTest
    static void testHierarchicalManagerLlmFailureFailsCrew() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('Manager LLM down');

        FC_Crew crew = buildHierarchicalCrew('Crew LLM Fail',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isFalse(result.success);
        Assert.isNotNull(result.errorMessage);
        Assert.isTrue(result.errorMessage.contains('Manager LLM down'));
    }

    // ─── 4. Unknown manager action → corrective message, then FINAL_ANSWER ──
    //        (covers line 70)

    @IsTest
    static void testHierarchicalUnknownActionThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();

        FC_ModelsAPIService.enqueueMock('{"action":"DO_SOMETHING_WEIRD"}');
        FC_ModelsAPIService.enqueueMock('{"action":"FINAL_ANSWER","summary":"Recovered"}');

        FC_Crew crew = buildHierarchicalCrew('Crew Unknown Action',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isTrue(result.success);
        Assert.isTrue(result.taskResults.isEmpty());
    }

    // ─── 5. Invalid JSON directive → corrective, then FINAL_ANSWER ───────────
    //        (covers parseDirective null branch)

    @IsTest
    static void testHierarchicalInvalidDirectiveThenDelegate() {
        FC_ModelsAPIService.clearMocks();

        FC_ModelsAPIService.enqueueMock('[]');
        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"Analyst"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Recovered"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"All done"}'
        );

        FC_Crew crew = buildHierarchicalCrew('Crew Invalid Directive',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isTrue(result.success);
        Assert.areEqual('Recovered', result.finalOutput);
    }

    // ─── 6. Delegate to unknown task → error message, then FINAL_ANSWER ──────
    //        (covers lines 96-100)

    @IsTest
    static void testHierarchicalDelegateToUnknownTaskThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();

        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"NonExistentTask","agent":"Analyst"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"Adjusted after unknown task"}'
        );

        FC_Crew crew = buildHierarchicalCrew('Crew Unknown Task',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isTrue(result.success);
        Assert.isTrue(result.taskResults.isEmpty());
    }

    // ─── 7. Delegate to unknown agent → error message, then FINAL_ANSWER ──────
    //        (covers lines 102-107)

    @IsTest
    static void testHierarchicalDelegateToUnknownAgentThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();

        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"NonExistentRole"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"Adjusted after unknown agent"}'
        );

        FC_Crew crew = buildHierarchicalCrew('Crew Unknown Agent',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isTrue(result.success);
        Assert.isTrue(result.taskResults.isEmpty());
    }

    // ─── 8. Delegated task FAILS → failure message to manager → FINAL_ANSWER ─
    //        (covers lines 126-131)

    @IsTest
    static void testHierarchicalDelegatedTaskFailsThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();

        // Manager: delegate
        FC_ModelsAPIService.enqueueMock(
            '{"action":"DELEGATE","task":"Task A","agent":"Analyst"}'
        );
        // Analyst: invalid JSON × 2 → hits maxIterations, task fails
        FC_ModelsAPIService.enqueueMock('[]');
        FC_ModelsAPIService.enqueueMock('[]');
        // Manager: receives failure message, then concludes
        FC_ModelsAPIService.enqueueMock(
            '{"action":"FINAL_ANSWER","summary":"Task failed but crew finished"}'
        );

        FC_Crew crew = buildHierarchicalCrew('Crew Task Fails',
            new List<FC_Agent>{ buildAgent('Analyst', 2) },
            new List<FC_Task>{  buildTask('Task A', 'Analyst') }
        );

        FC_CrewResult result = crew.kickoff();
        Assert.isTrue(result.success);
        Assert.areEqual(1, result.taskResults.size());
        Assert.isFalse(result.taskResults[0].success);
    }
}

