/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_CrewResultTest {

    @IsTest
    static void testCompleteAndFail() {
        FC_CrewResult result = new FC_CrewResult('My Crew');
        Assert.isFalse(result.success);

        result.complete('Final output', 1200L);
        Assert.isTrue(result.success);
        Assert.areEqual('Final output', result.finalOutput);
        Assert.areEqual(1200L, result.totalExecutionTimeMs);

        FC_CrewResult failed = new FC_CrewResult('Failed Crew');
        failed.fail('Something broke', 500L);
        Assert.isFalse(failed.success);
        Assert.areEqual('Something broke', failed.errorMessage);
    }

    @IsTest
    static void testGetLastTaskOutput() {
        FC_CrewResult result = new FC_CrewResult('Crew');

        FC_TaskResult t1 = new FC_TaskResult('T1', 'Do T1', 'Agent');
        t1.complete('Output 1', 100L);

        FC_TaskResult t2 = new FC_TaskResult('T2', 'Do T2', 'Agent');
        t2.fail('Failed', 200L);

        FC_TaskResult t3 = new FC_TaskResult('T3', 'Do T3', 'Agent');
        t3.complete('Output 3', 300L);

        result.addTaskResult(t1);
        result.addTaskResult(t2);
        result.addTaskResult(t3);

        Assert.areEqual('Output 3', result.getLastTaskOutput());
    }

    @IsTest
    static void testGetLastTaskOutputAllFailed() {
        FC_CrewResult result = new FC_CrewResult('Crew');
        FC_TaskResult t = new FC_TaskResult('T', 'Task', 'Agent');
        t.fail('Error', 100L);
        result.addTaskResult(t);

        Assert.isNull(result.getLastTaskOutput());
    }

    @IsTest
    static void testSuccessfulTaskCount() {
        FC_CrewResult result = new FC_CrewResult('Crew');

        FC_TaskResult t1 = new FC_TaskResult('T1', 'D', 'A');
        t1.complete('Out', 100L);
        FC_TaskResult t2 = new FC_TaskResult('T2', 'D', 'A');
        t2.fail('Err', 100L);

        result.addTaskResult(t1);
        result.addTaskResult(t2);

        Assert.areEqual(1, result.successfulTaskCount());
    }

    @IsTest
    static void testTotalToolCalls() {
        FC_CrewResult result = new FC_CrewResult('Crew');
        FC_TaskResult t = new FC_TaskResult('T', 'D', 'A');
        t.addStep(FC_StepResult.toolCall('thought', 'Tool1', null, 'result1'));
        t.addStep(FC_StepResult.toolCall('thought', 'Tool2', null, 'result2'));
        t.addStep(FC_StepResult.finalAnswer('thought', 'done'));
        t.complete('done', 300L);
        result.addTaskResult(t);

        Assert.areEqual(2, result.totalToolCalls());
    }
}
