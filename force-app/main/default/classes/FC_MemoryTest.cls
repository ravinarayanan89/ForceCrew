/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_MemoryTest {

    @IsTest
    static void testAddAndRetrieve() {
        FC_Memory memory = new FC_Memory();
        memory.add(FC_ChatMessage.system('You are an agent.'));
        memory.add(FC_ChatMessage.user('Hello'));
        memory.add(FC_ChatMessage.assistant('Hi there'));

        Assert.areEqual(3, memory.size());

        List<FC_ChatMessage> history = memory.getHistory();
        Assert.areEqual('system',    history[0].role);
        Assert.areEqual('user',      history[1].role);
        Assert.areEqual('assistant', history[2].role);
    }

    @IsTest
    static void testClearPreservesSystemMessages() {
        FC_Memory memory = new FC_Memory();
        memory.add(FC_ChatMessage.system('System prompt'));
        memory.add(FC_ChatMessage.user('User message'));
        memory.add(FC_ChatMessage.assistant('Assistant response'));

        memory.clear();

        Assert.areEqual(1, memory.size());
        Assert.areEqual('system', memory.getHistory()[0].role);
    }

    @IsTest
    static void testInjectContext() {
        FC_Memory memory = new FC_Memory();
        memory.injectContext('Prior Task', 'The result was 42.');

        Assert.areEqual(1, memory.size());
        Assert.isTrue(memory.getHistory()[0].content.contains('42'));
    }

    @IsTest
    static void testInjectContextBlankIgnored() {
        FC_Memory memory = new FC_Memory();
        memory.injectContext('Task', '');
        memory.injectContext('Task', null);
        Assert.areEqual(0, memory.size());
    }

    @IsTest
    static void testTrimOldestNonSystemMessages() {
        FC_Memory memory = new FC_Memory(5);  // max 5 messages
        memory.add(FC_ChatMessage.system('System'));

        // Add 5 user messages — will exceed limit after 5th non-system + the system message
        for (Integer i = 1; i <= 5; i++) {
            memory.add(FC_ChatMessage.user('Message ' + i));
        }

        // Total = 6 (1 system + 5 user), max = 5 → 1 oldest user should be trimmed
        Assert.areEqual(5, memory.size());

        List<FC_ChatMessage> history = memory.getHistory();
        // System message must be preserved
        Assert.areEqual('system', history[0].role);
        // Oldest user message (Message 1) should be gone
        Boolean foundMsg1 = false;
        for (FC_ChatMessage msg : history) {
            if (msg.content == 'Message 1') { foundMsg1 = true; }
        }
        Assert.isFalse(foundMsg1, 'Message 1 should have been trimmed');
    }

    @IsTest
    static void testGetHistoryReturnsClone() {
        FC_Memory memory = new FC_Memory();
        memory.add(FC_ChatMessage.user('Test'));

        List<FC_ChatMessage> h1 = memory.getHistory();
        List<FC_ChatMessage> h2 = memory.getHistory();

        // Modifying the returned list should not affect memory
        h1.add(FC_ChatMessage.user('Extra'));
        Assert.areEqual(1, memory.size());
    }

    @IsTest
    static void testIsEmpty() {
        FC_Memory memory = new FC_Memory();
        Assert.isTrue(memory.isEmpty());
        memory.add(FC_ChatMessage.user('Hi'));
        Assert.isFalse(memory.isEmpty());
    }
}
