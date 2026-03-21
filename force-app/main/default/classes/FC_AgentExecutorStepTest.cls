/**
 * FC_AgentExecutorStepTest - Tests for the single-step (governor-limit safe) executor.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_AgentExecutorStepTest {

    private static FC_Agent buildAgent() {
        return new FC_Agent.Builder('Analyst')
            .goal('Analyse data')
            .backstory('Expert analyst')
            .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))
            .maxIterations(5)
            .build();
    }

    private static FC_Task buildTask() {
        return new FC_Task.Builder('Fetch Accounts')
            .description('Query top accounts by revenue.')
            .expectedOutput('A list of account names.')
            .assignToAgent('Analyst')
            .build();
    }

    // ─── Initialise ───────────────────────────────────────────────────────────

    @IsTest
    static void testInitialiseBuildsHistory() {
        FC_Agent agent = buildAgent();
        FC_Task  task  = buildTask();

        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(agent);
        FC_StepRequest request = executor.initialise(task, null);

        Assert.areEqual('Analyst',       request.agentRole);
        Assert.areEqual('Fetch Accounts', request.taskName);
        Assert.areEqual(5,               request.maxIterations);
        Assert.areEqual(0,               request.iterationCount);
        Assert.isFalse(request.isComplete);
        Assert.isNull(request.errorMessage);

        // History should have 2 messages: system + user (task prompt)
        List<FC_ChatMessage> history = request.getHistory();
        Assert.areEqual(2, history.size());
        Assert.areEqual('system', history[0].role);
        Assert.areEqual('user',   history[1].role);
        Assert.isTrue(history[0].content.contains('Analyst'));   // system prompt has role
        Assert.isTrue(history[1].content.contains('Fetch Accounts')); // task name in prompt
    }

    @IsTest
    static void testInitialiseWithPriorContext() {
        FC_Agent agent = buildAgent();
        FC_Task  task  = new FC_Task.Builder('Summary')
            .description('Summarise the data')
            .withContext('Fetch Accounts')
            .build();

        Map<String, String> priorOutputs = new Map<String, String>{
            'Fetch Accounts' => 'Account A: $1M'
        };

        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(agent);
        FC_StepRequest request = executor.initialise(task, priorOutputs);

        List<FC_ChatMessage> history = request.getHistory();
        Assert.areEqual(2, history.size());
        // Context from prior task should be embedded in the user message
        Assert.isTrue(history[1].content.contains('Account A: $1M'));
    }

    @IsTest
    static void testInitialiseWithNullTask() {
        // buildTask is fine, just verifying null priorOutputs doesn't throw
        FC_Agent agent = buildAgent();
        FC_Task  task  = buildTask();

        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(agent);
        FC_StepRequest request = executor.initialise(task, null);

        Assert.isNotNull(request);
        Assert.isFalse(request.isComplete);
    }

    // ─── Step — Guard Conditions ──────────────────────────────────────────────

    @IsTest
    static void testStepWithNullRequestReturnsError() {
        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(buildAgent());
        FC_StepRequest result = executor.step(null);

        Assert.isNotNull(result.errorMessage);
    }

    @IsTest
    static void testStepAlreadyCompleteReturnsImmediately() {
        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(buildAgent());

        FC_StepRequest req = new FC_StepRequest();
        req.isComplete  = true;
        req.finalAnswer = 'Already done';

        FC_StepRequest result = executor.step(req);
        Assert.isTrue(result.isComplete);
        Assert.areEqual('Already done', result.finalAnswer);
    }

    @IsTest
    static void testStepMaxIterationsExceededReturnsError() {
        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(buildAgent());

        FC_StepRequest req    = new FC_StepRequest();
        req.iterationCount    = 5;
        req.maxIterations     = 5;  // already at limit
        req.agentRole         = 'Analyst';
        req.taskName          = 'Task';
        req.setHistory(new List<FC_ChatMessage>{ FC_ChatMessage.user('test') });

        FC_StepRequest result = executor.step(req);
        Assert.isNotNull(result.errorMessage);
        Assert.isTrue(result.errorMessage.contains('Max iterations'));
    }

    // ─── Step Request Serialisation (LWC transport simulation) ───────────────

    @IsTest
    static void testStepRequestSurvivesJsonRoundTrip() {
        FC_Agent agent = buildAgent();
        FC_Task  task  = buildTask();

        FC_AgentExecutorStep executor = new FC_AgentExecutorStep(agent);
        FC_StepRequest request = executor.initialise(task, null);

        // Simulate LWC serialising and deserialising between calls
        String serialised = JSON.serialize(request);
        FC_StepRequest restored = (FC_StepRequest) JSON.deserialize(serialised, FC_StepRequest.class);

        Assert.areEqual(request.agentRole,      restored.agentRole);
        Assert.areEqual(request.taskName,       restored.taskName);
        Assert.areEqual(request.maxIterations,  restored.maxIterations);
        Assert.areEqual(request.iterationCount, restored.iterationCount);
        Assert.isFalse(restored.isComplete);

        List<FC_ChatMessage> originalHistory = request.getHistory();
        List<FC_ChatMessage> restoredHistory = restored.getHistory();
        Assert.areEqual(originalHistory.size(), restoredHistory.size());
        Assert.areEqual(originalHistory[0].role,    restoredHistory[0].role);
        Assert.areEqual(originalHistory[0].content, restoredHistory[0].content);
    }
}
