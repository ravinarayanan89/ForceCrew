/**
 * FC_StepRequestTest - Tests for the step-by-step execution state object.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_StepRequestTest {

    @IsTest
    static void testDefaults() {
        FC_StepRequest req = new FC_StepRequest();
        Assert.isFalse(req.isComplete);
        Assert.areEqual(0,  req.iterationCount);
        Assert.areEqual(10, req.maxIterations);
        Assert.isNull(req.errorMessage);
        Assert.isNull(req.finalAnswer);
    }

    @IsTest
    static void testSetAndGetHistory() {
        FC_StepRequest req = new FC_StepRequest();

        List<FC_ChatMessage> messages = new List<FC_ChatMessage>{
            FC_ChatMessage.system('You are an agent.'),
            FC_ChatMessage.user('Do something.'),
            FC_ChatMessage.assistant('{"action":"FINAL_ANSWER","thought":"done","answer":"42"}')
        };

        req.setHistory(messages);
        Assert.isTrue(String.isNotBlank(req.historyJson));

        List<FC_ChatMessage> restored = req.getHistory();
        Assert.areEqual(3, restored.size());
        Assert.areEqual('system',    restored[0].role);
        Assert.areEqual('user',      restored[1].role);
        Assert.areEqual('assistant', restored[2].role);
        Assert.areEqual('You are an agent.', restored[0].content);
        Assert.areEqual('Do something.',     restored[1].content);
    }

    @IsTest
    static void testGetHistoryEmpty() {
        FC_StepRequest req = new FC_StepRequest();
        // No historyJson set
        List<FC_ChatMessage> history = req.getHistory();
        Assert.isNotNull(history);
        Assert.isTrue(history.isEmpty());
    }

    @IsTest
    static void testHistoryRoundTrip() {
        FC_StepRequest req = new FC_StepRequest();
        req.agentRole      = 'Analyst';
        req.taskName       = 'Fetch Data';
        req.maxIterations  = 5;
        req.iterationCount = 2;

        List<FC_ChatMessage> messages = new List<FC_ChatMessage>{
            FC_ChatMessage.system('System prompt'),
            FC_ChatMessage.user('Task prompt'),
            FC_ChatMessage.assistant('{"action":"TOOL_CALL","tool":"QueryRecords","parameters":{"query":"SELECT Id FROM Account"}}'),
            FC_ChatMessage.user('Tool result: {"success":true,"count":3}')
        };
        req.setHistory(messages);

        // Simulate JSON round-trip (as done by LWC → Apex)
        String serialised = JSON.serialize(req);
        FC_StepRequest restored = (FC_StepRequest) JSON.deserialize(serialised, FC_StepRequest.class);

        Assert.areEqual('Analyst',   restored.agentRole);
        Assert.areEqual('Fetch Data', restored.taskName);
        Assert.areEqual(5,           restored.maxIterations);
        Assert.areEqual(2,           restored.iterationCount);
        Assert.isFalse(restored.isComplete);

        List<FC_ChatMessage> restoredHistory = restored.getHistory();
        Assert.areEqual(4, restoredHistory.size());
        Assert.areEqual('system', restoredHistory[0].role);
        Assert.areEqual('System prompt', restoredHistory[0].content);
    }

    @IsTest
    static void testIsCompleteFlag() {
        FC_StepRequest req = new FC_StepRequest();
        req.isComplete  = true;
        req.finalAnswer = 'The answer is 42.';

        String json_x = JSON.serialize(req);
        FC_StepRequest restored = (FC_StepRequest) JSON.deserialize(json_x, FC_StepRequest.class);
        Assert.isTrue(restored.isComplete);
        Assert.areEqual('The answer is 42.', restored.finalAnswer);
    }
}
