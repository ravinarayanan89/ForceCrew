/**
 * SC_DMLToolTest - Unit tests for SC_DMLTool.
 *
 * Uses FC_CrewRun__c as the fixture object (a ForceCrew-owned custom object with
 * simple text/picklist fields) so these tests don't depend on any org-specific
 * validation rules on standard objects.
 *
 * @group SalesCycle Tests
 */
@IsTest
public class SC_DMLToolTest {

    @IsTest
    static void testGetNameDescriptionAndParameters() {
        SC_DMLTool tool = new SC_DMLTool();
        Assert.areEqual('DMLRecord', tool.getName());
        Assert.isTrue(String.isNotBlank(tool.getDescription()));

        List<FC_ToolParameter> params = tool.getParameters();
        Assert.areEqual(4, params.size());
    }

    @IsTest
    static void testExecuteInsertSuccess() {
        SC_DMLTool tool = new SC_DMLTool();
        Map<String, Object> params = new Map<String, Object>{
            'operation'     => 'insert',
            'objectApiName' => 'FC_CrewRun__c',
            'fields'        => '{"CrewName__c":"Test Crew","Status__c":"Pending"}'
        };

        String resultJson = tool.execute(params);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        Assert.isTrue((Boolean) result.get('success'));
        Id newId = (Id) String.valueOf(result.get('recordId'));

        FC_CrewRun__c inserted = [SELECT CrewName__c, Status__c FROM FC_CrewRun__c WHERE Id = :newId];
        Assert.areEqual('Test Crew', inserted.CrewName__c);
        Assert.areEqual('Pending', inserted.Status__c);
    }

    @IsTest
    static void testExecuteUpdateSuccess() {
        FC_CrewRun__c run = new FC_CrewRun__c(CrewName__c = 'Original Name', Status__c = 'Pending');
        insert run;

        SC_DMLTool tool = new SC_DMLTool();
        Map<String, Object> params = new Map<String, Object>{
            'operation'     => 'update',
            'objectApiName' => 'FC_CrewRun__c',
            'recordId'      => run.Id,
            'fields'        => '{"CrewName__c":"Updated Name"}'
        };

        String resultJson = tool.execute(params);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        Assert.isTrue((Boolean) result.get('success'));

        FC_CrewRun__c updated = [SELECT CrewName__c FROM FC_CrewRun__c WHERE Id = :run.Id];
        Assert.areEqual('Updated Name', updated.CrewName__c);
    }

    @IsTest
    static void testExecuteMissingRequiredParamsReturnErrors() {
        SC_DMLTool tool = new SC_DMLTool();

        assertError(tool.execute(new Map<String, Object>{
            'objectApiName' => 'FC_CrewRun__c', 'fields' => '{}'
        }), 'operation is required');

        assertError(tool.execute(new Map<String, Object>{
            'operation' => 'insert', 'fields' => '{}'
        }), 'objectApiName is required');

        assertError(tool.execute(new Map<String, Object>{
            'operation' => 'insert', 'objectApiName' => 'FC_CrewRun__c'
        }), 'fields (JSON) is required');
    }

    @IsTest
    static void testExecuteInvalidOperationReturnsError() {
        SC_DMLTool tool = new SC_DMLTool();
        String result = tool.execute(new Map<String, Object>{
            'operation' => 'delete', 'objectApiName' => 'FC_CrewRun__c', 'fields' => '{}'
        });
        assertError(result, 'operation must be "insert" or "update"');
    }

    @IsTest
    static void testExecuteUpdateMissingRecordIdReturnsError() {
        SC_DMLTool tool = new SC_DMLTool();
        String result = tool.execute(new Map<String, Object>{
            'operation' => 'update', 'objectApiName' => 'FC_CrewRun__c', 'fields' => '{"CrewName__c":"X"}'
        });
        assertError(result, 'recordId is required for update');
    }

    @IsTest
    static void testExecuteUnknownObjectApiNameReturnsError() {
        SC_DMLTool tool = new SC_DMLTool();
        String result = tool.execute(new Map<String, Object>{
            'operation' => 'insert', 'objectApiName' => 'NotARealObject__x', 'fields' => '{}'
        });
        assertError(result, 'Unknown object API name');
    }

    @IsTest
    static void testExecuteUnknownFieldReturnsError() {
        SC_DMLTool tool = new SC_DMLTool();
        String result = tool.execute(new Map<String, Object>{
            'operation' => 'insert', 'objectApiName' => 'FC_CrewRun__c',
            'fields' => '{"NotARealField__c":"value"}'
        });
        assertError(result, 'does not exist on FC_CrewRun__c');
    }

    @IsTest
    static void testExecuteInvalidFieldsJsonReturnsError() {
        SC_DMLTool tool = new SC_DMLTool();
        String result = tool.execute(new Map<String, Object>{
            'operation' => 'insert', 'objectApiName' => 'FC_CrewRun__c', 'fields' => 'not json'
        });
        assertError(result, 'Invalid JSON in fields parameter');
    }

    @IsTest
    static void testExecuteInvalidRecordIdFormatReturnsError() {
        SC_DMLTool tool = new SC_DMLTool();
        String result = tool.execute(new Map<String, Object>{
            'operation' => 'update', 'objectApiName' => 'FC_CrewRun__c',
            'recordId' => 'not-a-valid-id', 'fields' => '{"CrewName__c":"X"}'
        });
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) parsed.get('success'));
    }

    private static void assertError(String resultJson, String expectedSubstring) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        Assert.isFalse((Boolean) result.get('success'));
        Assert.isTrue(String.valueOf(result.get('error')).contains(expectedSubstring));
    }
}
