/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_TaskTest {

    @IsTest
    static void testBuilderDefaults() {
        FC_Task task = new FC_Task.Builder('My Task').build();

        Assert.areEqual('My Task', task.name);
        Assert.areEqual('My Task', task.description);  // defaults to name when blank
        Assert.isTrue(String.isNotBlank(task.expectedOutput));
        Assert.isNull(task.assignedAgentRole);
        Assert.isTrue(task.contextTaskNames.isEmpty());
    }

    @IsTest
    static void testBuilderFullConfig() {
        FC_Task task = new FC_Task.Builder('Fetch Data')
            .description('Query top accounts')
            .expectedOutput('JSON list')
            .assignToAgent('Analyst')
            .build();

        Assert.areEqual('Fetch Data',       task.name);
        Assert.areEqual('Query top accounts', task.description);
        Assert.areEqual('JSON list',        task.expectedOutput);
        Assert.areEqual('Analyst',          task.assignedAgentRole);
    }

    @IsTest
    static void testBlankNameThrows() {
        try {
            new FC_Task.Builder('').build();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('name'));
        }
    }

    @IsTest
    static void testWithContext() {
        FC_Task task = new FC_Task.Builder('Summary')
            .withContext('Fetch Data')
            .withContext('Analyse Data')
            .build();

        Assert.areEqual(2, task.contextTaskNames.size());
        Assert.isTrue(task.contextTaskNames.contains('Fetch Data'));
        Assert.isTrue(task.contextTaskNames.contains('Analyse Data'));
    }

    @IsTest
    static void testWithContextFrom() {
        FC_Task task = new FC_Task.Builder('Summary')
            .withContextFrom(new List<String>{ 'Task A', 'Task B' })
            .build();

        Assert.areEqual(2, task.contextTaskNames.size());
    }

    @IsTest
    static void testBlankContextIgnored() {
        FC_Task task = new FC_Task.Builder('Task').withContext('').withContext(null).build();
        Assert.isTrue(task.contextTaskNames.isEmpty());
    }

    @IsTest
    static void testBuildPromptNoContext() {
        FC_Task task = new FC_Task.Builder('Fetch Data')
            .description('Query accounts')
            .expectedOutput('Account list')
            .build();

        String prompt = task.buildPrompt(null);
        Assert.isTrue(prompt.contains('Fetch Data'));
        Assert.isTrue(prompt.contains('Query accounts'));
        Assert.isTrue(prompt.contains('Account list'));
        Assert.isFalse(prompt.contains('Context from Prior Tasks'));
    }

    @IsTest
    static void testBuildPromptWithContext() {
        FC_Task task = new FC_Task.Builder('Summary')
            .description('Summarise')
            .withContext('Fetch Data')
            .build();

        Map<String, String> priorOutputs = new Map<String, String>{
            'Fetch Data' => 'Account A: $1M, Account B: $2M'
        };

        String prompt = task.buildPrompt(priorOutputs);
        Assert.isTrue(prompt.contains('Context from Prior Tasks'));
        Assert.isTrue(prompt.contains('Fetch Data'));
        Assert.isTrue(prompt.contains('Account A: $1M'));
    }

    @IsTest
    static void testBuildPromptMissingContextGraceful() {
        FC_Task task = new FC_Task.Builder('Summary')
            .withContext('Missing Task')
            .build();

        // Should not error — missing context is simply omitted
        String prompt = task.buildPrompt(new Map<String, String>());
        Assert.isTrue(prompt.contains('Summary'));
        Assert.isFalse(prompt.contains('Context from Prior Tasks'));
    }

    @IsTest
    static void testBuildPromptNullPriorOutputs() {
        FC_Task task = new FC_Task.Builder('Task').withContext('Other').build();
        // Should not throw NPE
        String prompt = task.buildPrompt(null);
        Assert.isTrue(prompt.contains('Task'));
    }
}
