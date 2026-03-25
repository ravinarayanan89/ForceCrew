/**
 * ForceCrewTest - Unit tests for the ForceCrew library facade.
 *
 * ForceCrew is the public entry point for the framework — used by callers who
 * want a one-liner to run a single agent without assembling a full crew.
 * FC_CrewController.getFrameworkInfo() also delegates to ForceCrew.about().
 *
 * @group ForceCrew Tests
 */
@IsTest
public class ForceCrewTest {

    @IsTest
    static void testAboutContainsVersion() {
        String info = ForceCrew.about();
        Assert.isTrue(String.isNotBlank(info));
        Assert.isTrue(info.contains(ForceCrew.VERSION));
        Assert.isTrue(info.contains('ForceCrew'));
    }

    @IsTest
    static void testRunAgentSuccessWithNoTools() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"Hello World"}'
        );

        String answer = ForceCrew.runAgent(
            'Assistant',
            'Help users',
            'Friendly AI',
            null,
            'Say hello',
            'A greeting'
        );

        Assert.areEqual('Hello World', answer);
    }

    @IsTest
    static void testRunAgentSuccessWithTools() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock(
            '{"thought":"t","action":"FINAL_ANSWER","answer":"With tools answer"}'
        );

        List<FC_Tool> tools = new List<FC_Tool>{
            FC_Tool.fromMCP(new FC_SampleSOQLTool())
        };

        String answer = ForceCrew.runAgent(
            'Analyst',
            'Analyse data',
            'Expert analyst',
            tools,
            'Do analysis',
            'JSON result'
        );

        Assert.areEqual('With tools answer', answer);
    }

    @IsTest
    static void testRunAgentFailureReturnsErrorString() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('LLM down');

        String answer = ForceCrew.runAgent(
            'Analyst',
            'Analyse',
            'Expert',
            null,
            'Do work',
            'Output'
        );

        Assert.isTrue(answer.startsWith('Error:'));
        Assert.isTrue(answer.contains('LLM down'));
    }
}
