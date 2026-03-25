/**
 * FC_CrewControllerTest - Unit tests for FC_CrewController.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_CrewControllerTest {

    @IsTest
    static void testGetFrameworkInfoNotBlank() {
        String info = FC_CrewController.getFrameworkInfo();
        Assert.isTrue(String.isNotBlank(info));
        Assert.isTrue(info.contains('ForceCrew v'));
    }

    @IsTest
    static void testRunSingleAgentReturnsDto() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"SingleAgent OK"}'
        );

        FC_CrewController.CrewResultDTO dto = FC_CrewController.runSingleAgent(
            'Analyst',
            'Goal',
            'Backstory',
            null,
            'Do the thing',
            'Expected format'
        );

        Assert.isTrue(dto.success);
        Assert.areEqual('SingleAgent OK', dto.finalOutput);
        Assert.isTrue(dto.taskCount > 0);
        Assert.isNotNull(dto.tasks);
        Assert.areEqual(1, dto.tasks.size());
        Assert.isTrue(dto.tasks[0].success);
    }

    @IsTest
    static void testRunCrewFromConfigBuildsSequentialCrew() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Task A Out"}'
        );
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t2","action":"FINAL_ANSWER","answer":"Task B Out"}'
        );

        Map<String, Object> cfg = new Map<String, Object>();
        cfg.put('crewName', 'Crew From Config');
        cfg.put('process', 'SEQUENTIAL');
        cfg.put('verbose', false);

        Map<String, Object> agent1 = new Map<String, Object>();
        agent1.put('role', 'Analyst');
        agent1.put('goal', 'Goal A');
        agent1.put('backstory', 'Backstory A');
        agent1.put('toolClasses', new List<Object>());
        cfg.put('agents', new List<Object>{ agent1 });

        Map<String, Object> taskA = new Map<String, Object>();
        taskA.put('name', 'Task A');
        taskA.put('description', 'Do A');
        taskA.put('expectedOutput', 'Out A');
        taskA.put('assignToAgent', 'Analyst');

        Map<String, Object> taskB = new Map<String, Object>();
        taskB.put('name', 'Task B');
        taskB.put('description', 'Do B');
        taskB.put('expectedOutput', 'Out B');
        taskB.put('assignToAgent', 'Analyst');
        taskB.put('contextTasks', new List<Object>{ 'Task A' });

        cfg.put('tasks', new List<Object>{ taskA, taskB });
        cfg.put('inputs', new Map<String, Object>{ 'seed' => 'x' });

        FC_CrewController.CrewResultDTO dto =
            FC_CrewController.runCrewFromConfig(JSON.serialize(cfg));

        Assert.isTrue(dto.success);
        Assert.areEqual('Task B Out', dto.finalOutput);
        Assert.areEqual(2, dto.taskCount);
        Assert.areEqual(2, dto.successfulTasks);
        Assert.areEqual('Task A Out', dto.tasks[0].output);
        Assert.areEqual('Task B Out', dto.tasks[1].output);
    }

    @IsTest
    static void testInitAndRunAgentStep() {
        Map<String, Object> agentCfg = new Map<String, Object>{
            'role' => 'Analyst',
            'goal' => 'Goal',
            'backstory' => 'Backstory'
        };
        Map<String, Object> taskCfg = new Map<String, Object>{
            'name' => 'My Task',
            'description' => 'Do it',
            'expectedOutput' => 'Answer',
            'assignToAgent' => 'Analyst'
        };

        String priorOutputsJson = null;
        FC_StepRequest init =
            FC_CrewController.initAgentStep(
                JSON.serialize(agentCfg),
                JSON.serialize(taskCfg),
                priorOutputsJson
            );
        Assert.isFalse(init.isComplete);
        Assert.isNull(init.errorMessage);
        Assert.isNotNull(init.historyJson);

        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Step OK"}'
        );

        FC_StepRequest stepped = FC_CrewController.runAgentStep(
            JSON.serialize(agentCfg),
            JSON.serialize(init)
        );

        Assert.isTrue(stepped.isComplete);
        Assert.areEqual('Step OK', stepped.finalAnswer);
    }

    @IsTest
    static void testEnqueueCrewAsyncFailFastDoesNotCallLlm() {
        // Ensure the queued job fails fast due to missing agent role mapping,
        // so FC_AgentExecutor/ModelsAPI are not invoked.
        Map<String, Object> cfg = new Map<String, Object>();
        cfg.put('crewName', 'Async Crew Controller');
        cfg.put('process', 'SEQUENTIAL');
        cfg.put('verbose', false);

        Map<String, Object> agent1 = new Map<String, Object>();
        agent1.put('role', 'Analyst');
        agent1.put('goal', 'Goal');
        agent1.put('backstory', 'Backstory');
        agent1.put('toolClasses', new List<Object>());
        cfg.put('agents', new List<Object>{ agent1 });

        Map<String, Object> taskA = new Map<String, Object>();
        taskA.put('name', 'Task A');
        taskA.put('description', 'Do A');
        taskA.put('expectedOutput', 'Out A');
        // Unknown assigned agent role -> queueable execute resolves to null and finalises as Failed.
        taskA.put('assignToAgent', 'UnknownRole');
        taskA.put('contextTasks', new List<Object>());
        cfg.put('tasks', new List<Object>{ taskA });

        FC_ModelsAPIService.clearMocks();

        Test.startTest();
        Id runId = Id.valueOf(
            FC_CrewController.enqueueCrewAsync(JSON.serialize(cfg), 'CORR-CONTROLLER')
        );
        Test.stopTest();

        FC_CrewRun__c run = [
            SELECT Status__c, ErrorMessage__c
            FROM FC_CrewRun__c
            WHERE Id = :runId
        ];

        Assert.areEqual(FC_CrewQueueable.STATUS_FAILED, run.Status__c);
        Assert.isNotNull(run.ErrorMessage__c);
        Assert.isTrue(run.ErrorMessage__c.contains('No agent with role'));
    }
}

