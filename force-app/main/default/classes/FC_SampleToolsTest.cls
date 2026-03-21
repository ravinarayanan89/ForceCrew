/**
 * Tests for FC_SampleSOQLTool and FC_SampleDescribeTool.
 *
 * @group ForceCrew Tests
 */
@IsTest
public class FC_SampleToolsTest {

    // ─── FC_SampleSOQLTool ────────────────────────────────────────────────────

    @IsTest
    static void testSOQLToolSchema() {
        FC_SampleSOQLTool tool = new FC_SampleSOQLTool();

        Assert.areEqual('QueryRecords', tool.getName());
        Assert.isTrue(String.isNotBlank(tool.getDescription()));
        Assert.areEqual(1, tool.getParameters().size());
        Assert.areEqual('query', tool.getParameters()[0].name);
        Assert.isTrue(tool.getParameters()[0].required);
    }

    @IsTest
    static void testSOQLToolExecutesQuery() {
        String result = new FC_SampleSOQLTool().execute(
            new Map<String, Object>{ 'query' => 'SELECT Id FROM Account LIMIT 1' }
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) parsed.get('success'));
        Assert.isNotNull(parsed.get('count'));
    }

    @IsTest
    static void testSOQLToolAppendsLimit() {
        // A query without LIMIT — tool should add LIMIT 200 silently
        String result = new FC_SampleSOQLTool().execute(
            new Map<String, Object>{ 'query' => 'SELECT Id FROM Account' }
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) parsed.get('success'));
    }

    @IsTest
    static void testSOQLToolMissingQueryParam() {
        String result = new FC_SampleSOQLTool().execute(new Map<String, Object>());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) parsed.get('success'));
        Assert.isTrue(((String) parsed.get('error')).contains('"query"'));
    }

    @IsTest
    static void testSOQLToolInvalidQuery() {
        String result = new FC_SampleSOQLTool().execute(
            new Map<String, Object>{ 'query' => 'THIS IS NOT SOQL' }
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) parsed.get('success'));
        Assert.isNotNull(parsed.get('error'));
    }

    // ─── FC_SampleDescribeTool ────────────────────────────────────────────────

    @IsTest
    static void testDescribeToolSchema() {
        FC_SampleDescribeTool tool = new FC_SampleDescribeTool();

        Assert.areEqual('DescribeObject', tool.getName());
        Assert.isTrue(String.isNotBlank(tool.getDescription()));
        Assert.areEqual(1, tool.getParameters().size());
        Assert.areEqual('objectType', tool.getParameters()[0].name);
        Assert.isTrue(tool.getParameters()[0].required);
    }

    @IsTest
    static void testDescribeToolAccount() {
        String result = new FC_SampleDescribeTool().execute(
            new Map<String, Object>{ 'objectType' => 'Account' }
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) parsed.get('success'));
        Assert.areEqual('Account', parsed.get('objectType'));
        Assert.isTrue(((Integer) parsed.get('fieldCount')) > 0);
    }

    @IsTest
    static void testDescribeToolUnknownObject() {
        String result = new FC_SampleDescribeTool().execute(
            new Map<String, Object>{ 'objectType' => 'FakeObject__c_XYZ' }
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) parsed.get('success'));
        Assert.isTrue(((String) parsed.get('error')).contains('not found'));
    }

    @IsTest
    static void testDescribeToolMissingParam() {
        String result = new FC_SampleDescribeTool().execute(new Map<String, Object>());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) parsed.get('success'));
    }
}
