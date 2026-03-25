/**
 * FC_ModelsAPIServiceTest - Unit tests for FC_ModelsAPIService.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_ModelsAPIServiceTest {

    @IsTest
    static void testChatNoMessagesReturnsFailure() {
        FC_ModelsAPIService service = new FC_ModelsAPIService();

        FC_ModelsAPIService.ChatResponse r1 = service.chat(new List<FC_ChatMessage>());
        Assert.isFalse(r1.isSuccess);
        Assert.isTrue(String.isNotBlank(r1.errorMessage));
        Assert.isTrue(r1.errorMessage.contains('No messages provided'));

        FC_ModelsAPIService.ChatResponse r2 = service.chat(null);
        Assert.isFalse(r2.isSuccess);
        Assert.isTrue(String.isNotBlank(r2.errorMessage));
        Assert.isTrue(r2.errorMessage.contains('No messages provided'));
    }

    @IsTest
    static void testChatUsesMockQueueSuccess() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMock('MOCK_OK');

        List<FC_ChatMessage> messages = new List<FC_ChatMessage>{
            FC_ChatMessage.user('Hello')
        };

        FC_ModelsAPIService service =
            new FC_ModelsAPIService(FC_ModelsAPIService.MODEL_GPT4O_MINI);

        FC_ModelsAPIService.ChatResponse r = service.chat(messages);
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('MOCK_OK', r.content);
        Assert.isNotNull(r.generationId);
        Assert.isTrue(String.isNotBlank(r.generationId));
        Assert.isNull(r.errorMessage);
    }

    @IsTest
    static void testChatUsesMockQueueFailure() {
        FC_ModelsAPIService.clearMocks();
        FC_ModelsAPIService.enqueueMockFailure('MOCK_FAIL');

        List<FC_ChatMessage> messages = new List<FC_ChatMessage>{
            FC_ChatMessage.user('Hello')
        };

        FC_ModelsAPIService service = new FC_ModelsAPIService();
        FC_ModelsAPIService.ChatResponse r = service.chat(messages);

        Assert.isFalse(r.isSuccess);
        Assert.areEqual('MOCK_FAIL', r.errorMessage);
        Assert.isTrue(String.isBlank(r.content));
    }

    @IsTest
    static void testChatNonMockPathReturnsFailureAndBuildsRequest() {
        // Ensure mock seam is not used.
        FC_ModelsAPIService.clearMocks();

        // Cover constructor defaulting branch (blank model -> default model).
        FC_ModelsAPIService service = new FC_ModelsAPIService('   ');

        List<FC_ChatMessage> messages = new List<FC_ChatMessage>{
            FC_ChatMessage.system('You are a helpful assistant.'),
            FC_ChatMessage.user('Say hi.')
        };

        Test.startTest();
        FC_ModelsAPIService.ChatResponse r = service.chat(messages);
        Test.stopTest();

        Assert.isNotNull(r);
        Assert.isFalse(r.isSuccess);
        Assert.isTrue(String.isNotBlank(r.errorMessage));
        // The exact text can vary by org/runtime restrictions, but should mention Models API.
        Assert.isTrue(r.errorMessage.contains('Models API') || r.errorMessage.contains('Models'));
    }
}

