/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_CrewTest {

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static FC_Agent makeAgent(String role) {
        return new FC_Agent.Builder(role)
            .goal('Complete tasks as ' + role)
            .backstory('I am a ' + role)
            .build();
    }

    private static FC_Task makeTask(String name, String agentRole) {
        return new FC_Task.Builder(name)
            .description('Do: ' + name)
            .expectedOutput('Output for ' + name)
            .assignToAgent(agentRole)
            .build();
    }

    // ─── Builder Tests ────────────────────────────────────────────────────────

    @IsTest
    static void testBuilderCreatesCrewWithDefaults() {
        FC_Crew crew = new FC_Crew.Builder('Test Crew')
            .agent(makeAgent('Analyst'))
            .task(makeTask('Task1', 'Analyst'))
            .build();

        Assert.areEqual('Test Crew',                  crew.getName());
        Assert.areEqual(FC_Process.Type.SEQUENTIAL,   crew.getProcess());
        Assert.isFalse(crew.isVerbose());
        Assert.isTrue(crew.isFailFast());
        Assert.areEqual(1, crew.getAgents().size());
        Assert.areEqual(1, crew.getTasks().size());
    }

    @IsTest
    static void testBuilderFullConfig() {
        FC_Crew crew = new FC_Crew.Builder('Full Crew')
            .process(FC_Process.Type.HIERARCHICAL)
            .agent(makeAgent('A'))
            .task(makeTask('T', 'A'))
            .verbose(true)
            .failFast(false)
            .managerLlmModel('sfdc_ai__DefaultGPT4OmniMini')
            .build();

        Assert.areEqual(FC_Process.Type.HIERARCHICAL,       crew.getProcess());
        Assert.isTrue(crew.isVerbose());
        Assert.isFalse(crew.isFailFast());
        Assert.areEqual('sfdc_ai__DefaultGPT4OmniMini',     crew.getManagerLlmModel());
    }

    @IsTest
    static void testBuilderThrowsOnBlankName() {
        try {
            new FC_Crew.Builder('').agent(makeAgent('A')).task(makeTask('T', 'A')).build();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('name'));
        }
    }

    @IsTest
    static void testBuilderThrowsWithNoAgents() {
        try {
            new FC_Crew.Builder('Crew').task(makeTask('T', 'A')).build();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('agent'));
        }
    }

    @IsTest
    static void testBuilderThrowsWithNoTasks() {
        try {
            new FC_Crew.Builder('Crew').agent(makeAgent('A')).build();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('task'));
        }
    }

    @IsTest
    static void testHierarchicalDefaultsManagerModel() {
        FC_Crew crew = new FC_Crew.Builder('H Crew')
            .process(FC_Process.Type.HIERARCHICAL)
            .agent(makeAgent('A'))
            .task(makeTask('T', 'A'))
            .build();

        Assert.isNotNull(crew.getManagerLlmModel());
    }

    // ─── Validation Tests ─────────────────────────────────────────────────────

    @IsTest
    static void testValidationRejectsDuplicateAgentRoles() {
        FC_Crew crew = new FC_Crew.Builder('Dup Crew')
            .agent(makeAgent('Analyst'))
            .agent(makeAgent('Analyst'))
            .task(makeTask('T', 'Analyst'))
            .build();

        try {
            crew.kickoff();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('Duplicate agent role'));
        }
    }

    @IsTest
    static void testValidationRejectsDuplicateTaskNames() {
        FC_Crew crew = new FC_Crew.Builder('Dup Task Crew')
            .agent(makeAgent('Analyst'))
            .task(makeTask('SameName', 'Analyst'))
            .task(makeTask('SameName', 'Analyst'))
            .build();

        try {
            crew.kickoff();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('Duplicate task name'));
        }
    }

    @IsTest
    static void testValidationRejectsTaskWithUnknownAgentRole() {
        FC_Crew crew = new FC_Crew.Builder('Bad Role Crew')
            .agent(makeAgent('Analyst'))
            .task(makeTask('Task', 'NonExistentRole'))
            .build();

        try {
            crew.kickoff();
            Assert.fail('Expected AgentNotFoundException');
        } catch (FC_Exception.AgentNotFoundException e) {
            Assert.isTrue(e.getMessage().contains('NonExistentRole'));
        }
    }

    // ─── Lookup Tests ─────────────────────────────────────────────────────────

    @IsTest
    static void testGetAgentByRole() {
        FC_Crew crew = new FC_Crew.Builder('Crew')
            .agent(makeAgent('Researcher'))
            .agent(makeAgent('Writer'))
            .task(makeTask('T', 'Researcher'))
            .build();

        Assert.isNotNull(crew.getAgent('Researcher'));
        Assert.isNotNull(crew.getAgent('Writer'));
        Assert.isNull(crew.getAgent('Designer'));
    }

    @IsTest
    static void testGetTaskByName() {
        FC_Crew crew = new FC_Crew.Builder('Crew')
            .agent(makeAgent('A'))
            .task(makeTask('Alpha', 'A'))
            .task(makeTask('Beta', 'A'))
            .build();

        Assert.isNotNull(crew.getTask('Alpha'));
        Assert.isNotNull(crew.getTask('Beta'));
        Assert.isNull(crew.getTask('Gamma'));
    }

    @IsTest
    static void testNullAgentAndTaskIgnored() {
        FC_Crew crew = new FC_Crew.Builder('Crew')
            .agent(null)
            .agent(makeAgent('A'))
            .task(null)
            .task(makeTask('T', 'A'))
            .build();

        Assert.areEqual(1, crew.getAgents().size());
        Assert.areEqual(1, crew.getTasks().size());
    }
}
