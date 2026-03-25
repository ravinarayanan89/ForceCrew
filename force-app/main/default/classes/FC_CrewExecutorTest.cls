/**
 * FC_CrewExecutorTest - Unit tests for FC_CrewExecutor.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_CrewExecutorTest {

    private static FC_Agent buildAgent(String role, Integer maxIterations) {
        return new FC_Agent.Builder(role)
            .goal('Test goal')
            .backstory('Test backstory')
            .maxIterations(maxIterations)
            .build();
    }

    private static FC_Task buildTask(String name, String assignedRole, String expectedAction) {
        return new FC_Task.Builder(name)
            .description('Test task ' + name)
            .expectedOutput(expectedAction)
            .assignToAgent(assignedRole)
            .build();
    }

    @IsTest
    static void testSequentialSuccessUsesLastTaskOutput() {
        FC_ModelsAPIService.clearMocks();

        // Task A
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"A-out"}'
        );
        // Task B
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t2","action":"FINAL_ANSWER","answer":"B-out"}'
        );

        FC_Agent agent = buildAgent('Analyst', 2);
        FC_Task taskA = new FC_Task.Builder('Task A')
            .description('Do A')
            .expectedOutput('Output A')
            .assignToAgent('Analyst')
            .build();

        FC_Task taskB = new FC_Task.Builder('Task B')
            .description('Do B')
            .expectedOutput('Output B')
            .assignToAgent('Analyst')
            .withContext('Task A')
            .build();

        FC_Crew crew = new FC_Crew.Builder('Crew Exec Seq')
            .verbose(false)
            .failFast(true)
            .agent(agent)
            .task(taskA)
            .task(taskB)
            .build();

        FC_CrewResult result = crew.kickoff();

        Assert.isTrue(result.success);
        Assert.areEqual('B-out', result.finalOutput);
        Assert.areEqual(2, result.taskResults.size());
        Assert.areEqual(2, result.successfulTaskCount());
    }

    @IsTest
    static void testSequentialFailFastTrueAbortsOnTaskFailure() {
        FC_ModelsAPIService.clearMocks();

        // Task A succeeds (single call)
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"A-out"}'
        );
        // Task B fails (two invalid iterations to hit maxIterations)
        FC_ModelsAPIService.enqueueMock('[]');
        FC_ModelsAPIService.enqueueMock('[]');

        FC_Agent agent = buildAgent('Analyst', 2);

        FC_Task taskA = new FC_Task.Builder('Task A')
            .description('Do A')
            .expectedOutput('Output A')
            .assignToAgent('Analyst')
            .build();

        FC_Task taskB = new FC_Task.Builder('Task B')
            .description('Do B')
            .expectedOutput('Output B')
            .assignToAgent('Analyst')
            .build();

        FC_Crew crew = new FC_Crew.Builder('Crew Exec FailFast')
            .verbose(false)
            .failFast(true)
            .agent(agent)
            .task(taskA)
            .task(taskB)
            .build();

        FC_CrewResult result = crew.kickoff();

        Assert.isFalse(result.success);
        Assert.isNotNull(result.errorMessage);
        Assert.isTrue(result.errorMessage.contains('Task "Task B" failed'));
    }

    @IsTest
    static void testSequentialFailFastFalseContinuesAndFinalOutputIsLastSuccessful() {
        FC_ModelsAPIService.clearMocks();

        // Task A succeeds
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"A-out"}'
        );
        // Task B fails
        FC_ModelsAPIService.enqueueMock('[]');
        FC_ModelsAPIService.enqueueMock('[]');

        FC_Agent agent = buildAgent('Analyst', 2);

        FC_Task taskA = new FC_Task.Builder('Task A')
            .description('Do A')
            .expectedOutput('Output A')
            .assignToAgent('Analyst')
            .build();

        FC_Task taskB = new FC_Task.Builder('Task B')
            .description('Do B')
            .expectedOutput('Output B')
            .assignToAgent('Analyst')
            .build();

        FC_Crew crew = new FC_Crew.Builder('Crew Exec Continue')
            .verbose(false)
            .failFast(false)
            .agent(agent)
            .task(taskA)
            .task(taskB)
            .build();

        FC_CrewResult result = crew.kickoff();

        Assert.isTrue(result.success);
        Assert.areEqual('A-out', result.finalOutput);
        Assert.areEqual(2, result.taskResults.size());
        Assert.areEqual(1, result.successfulTaskCount());
        Assert.isFalse(result.taskResults[1].success);
    }
}

