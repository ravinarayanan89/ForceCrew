/**
 * FC_StepResultTest - Direct unit tests for FC_StepResult factory methods.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_StepResultTest {

    @IsTest
    static void testToolCallFactorySetsFields() {
        Map<String, Object> params = new Map<String, Object>{
            'query' => 'SELECT Id FROM Account LIMIT 1'
        };

        FC_StepResult step = FC_StepResult.toolCall(
            'thinking',
            'QueryRecords',
            params,
            '{"success":true}'
        );

        Assert.areEqual(FC_StepResult.StepType.TOOL_CALL, step.stepType);
        Assert.areEqual('thinking', step.thought);
        Assert.areEqual('QueryRecords', step.toolName);
        Assert.isNotNull(step.toolParameters);
        Assert.areEqual(1, step.toolParameters.size());
        Assert.areEqual('SELECT Id FROM Account LIMIT 1', String.valueOf(step.toolParameters.get('query')));
        Assert.areEqual('{"success":true}', step.toolResult);
        Assert.isTrue(step.success);
        Assert.isNull(step.errorMessage);
    }

    @IsTest
    static void testFinalAnswerFactorySetsFields() {
        FC_StepResult step = FC_StepResult.finalAnswer('finalThought', 'Final answer text');

        Assert.areEqual(FC_StepResult.StepType.FINAL_ANSWER, step.stepType);
        Assert.areEqual('finalThought', step.thought);
        Assert.areEqual('Final answer text', step.answer);
        Assert.isTrue(step.success);
        Assert.isNull(step.errorMessage);
    }

    @IsTest
    static void testErrorFactorySetsFields() {
        FC_StepResult step = FC_StepResult.error('Something broke', '{"raw":"x"}');

        Assert.areEqual(FC_StepResult.StepType.ERROR, step.stepType);
        Assert.isFalse(step.success);
        Assert.areEqual('Something broke', step.errorMessage);
        Assert.areEqual('{"raw":"x"}', step.rawLlmResponse);
    }

    @IsTest
    static void testSetRawLlmResponseUpdatesField() {
        FC_StepResult step = FC_StepResult.finalAnswer('thought', 'answer');
        step.setRawLlmResponse('RAW_RESPONSE');
        Assert.areEqual('RAW_RESPONSE', step.rawLlmResponse);
    }
}

