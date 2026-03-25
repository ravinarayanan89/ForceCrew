/**
 * FC_AgentExecutorTest - Unit tests for FC_AgentExecutor.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_AgentExecutorTest {

    private static FC_Agent buildAgent(String role) {
        return new FC_Agent.Builder(role)
            .goal('Test goal')
            .backstory('Test backstory')
            .maxIterations(2)
            .build();
    }

    private static FC_Agent buildToolAgent(String role) {
        return new FC_Agent.Builder(role)
            .goal('Test goal')
            .backstory('Test backstory')
            .maxIterations(2)
            .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
            .build();
    }

    private static FC_Task buildTask(String taskName, String agentRole) {
        return new FC_Task.Builder(taskName)
            .description('Test task')
            .expectedOutput('Test output')
            .assignToAgent(agentRole)
            .build();
    }

    @IsTest
    static void testExecuteToolCallThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();

        // 1) Ask to call tool
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"TOOL_CALL","tool":"QueryRecords",'
            + '"parameters":{"query":"SELECT Id FROM Account LIMIT 1"}}'
        );
        // 2) Final answer after tool result
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t2","action":"FINAL_ANSWER","answer":"Tool path OK"}'
        );

        FC_Agent agent = buildToolAgent('Analyst');
        FC_Task task = buildTask('Task A', 'Analyst');

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult result = executor.execute(task, null);

        Assert.isTrue(result.success);
        Assert.areEqual('Tool path OK', result.output);
        Assert.areEqual(1, result.toolCallCount());
        Assert.areEqual(2, result.steps.size());
        Assert.areEqual(FC_StepResult.StepType.TOOL_CALL, result.steps[0].stepType);
        Assert.areEqual(FC_StepResult.StepType.FINAL_ANSWER, result.steps[1].stepType);
    }

    @IsTest
    static void testExecuteInvalidJsonRetriesThenFails() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock('[]');
        FC_ModelsAPIService.enqueueMock('[]');

        FC_Agent agent = buildAgent('Analyst');
        FC_Task task = buildTask('Task Invalid', 'Analyst');

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult result = executor.execute(task, null);

        Assert.isFalse(result.success);
        Assert.isNotNull(result.errorMessage);
        Assert.isTrue(result.errorMessage.contains('exceeded max iterations'));
        Assert.areEqual(2, result.steps.size());
        Assert.areEqual(FC_StepResult.StepType.ERROR, result.steps[0].stepType);
        Assert.areEqual(FC_StepResult.StepType.ERROR, result.steps[1].stepType);
    }

    @IsTest
    static void testExecuteLlmFailureFailsTask() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('LLM failure');

        FC_Agent agent = buildAgent('Analyst');
        FC_Task task = buildTask('Task LLM Fail', 'Analyst');

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult result = executor.execute(task, null);

        Assert.isFalse(result.success);
        Assert.isNotNull(result.errorMessage);
        Assert.isTrue(result.errorMessage.contains('LLM failure'));
    }

    @IsTest
    static void testExecuteParsesMarkdownFencedJsonFinalAnswer() {
        FC_ModelsAPIService.clearMocks();
        String fenced = '```json\n'
            + '{"thought":"t","action":"FINAL_ANSWER","answer":"Markdown OK"}'
            + '\n```';
        FC_ModelsAPIService.enqueueMock(fenced);

        FC_Agent agent = buildAgent('Analyst');
        FC_Task task = buildTask('Task Markdown', 'Analyst');

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult result = executor.execute(task, null);

        Assert.isTrue(result.success);
        Assert.areEqual('Markdown OK', result.output);
    }

    @IsTest
    static void testExecuteToolCallWithBlankToolContinuesAndThenFinalAnswer() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"TOOL_CALL","tool":"   ","parameters":{}}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t2","action":"FINAL_ANSWER","answer":"Recovered"}'
        );

        FC_Agent agent = buildAgent('Analyst');
        FC_Task task = buildTask('Task Blank Tool', 'Analyst');

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult result = executor.execute(task, null);

        Assert.isTrue(result.success);
        Assert.areEqual('Recovered', result.output);
        Assert.areEqual(0, result.toolCallCount());
    }

    @IsTest
    static void testExecuteUnknownActionRetriesThenFailsMaxIterations() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock('{"thought":"t","action":"NOPE"}');
        FC_ModelsAPIService.enqueueMock('{"thought":"t","action":"NOPE"}');

        FC_Agent agent = buildAgent('Analyst');
        FC_Task task = buildTask('Task Unknown', 'Analyst');

        FC_AgentExecutor executor = new FC_AgentExecutor(agent);
        FC_TaskResult result = executor.execute(task, null);

        Assert.isFalse(result.success);
        Assert.isNotNull(result.errorMessage);
        Assert.isTrue(result.errorMessage.contains('without a FINAL_ANSWER'));
    }
}

