/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_ToolTest {

    @IsTest
    static void testFromMCPDerivedMetadata() {
        FC_Tool tool = FC_Tool.fromMCP(new FC_SampleSOQLTool());

        Assert.areEqual('QueryRecords', tool.getName());
        Assert.isTrue(String.isNotBlank(tool.getDescription()));
        Assert.areEqual(1, tool.getParameters().size());
        Assert.areEqual('query', tool.getParameters()[0].name);
    }

    @IsTest
    static void testFromPlainITool() {
        FC_Tool tool = FC_Tool.create('MyTool', 'Does something', new FC_SampleSOQLTool());

        Assert.areEqual('MyTool', tool.getName());
        Assert.areEqual('Does something', tool.getDescription());
        Assert.isTrue(tool.getParameters().isEmpty());
    }

    @IsTest
    static void testFromWithParameters() {
        List<FC_ToolParameter> params = new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('input', FC_ToolParameter.TYPE_STRING).required().build()
        };
        FC_Tool tool = FC_Tool.create('ParamTool', 'A parameterised tool', params, new FC_SampleSOQLTool());

        Assert.areEqual(1, tool.getParameters().size());
    }

    @IsTest
    static void testBlankNameThrows() {
        try {
            FC_Tool.create('', 'desc', new FC_SampleSOQLTool());
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('name'));
        }
    }

    @IsTest
    static void testNullImplThrows() {
        try {
            FC_Tool.create('Tool', 'desc', null);
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('implementation'));
        }
    }

    @IsTest
    static void testNullMCPToolThrows() {
        try {
            FC_Tool.fromMCP(null);
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void testFromClassNameMCP() {
        FC_Tool tool = FC_Tool.fromClassName('FC_SampleSOQLTool');
        Assert.areEqual('QueryRecords', tool.getName());
    }

    @IsTest
    static void testFromClassNameNotFound() {
        try {
            FC_Tool.fromClassName('NonExistentClassName_XYZ');
            Assert.fail('Expected ToolNotFoundException');
        } catch (FC_Exception.ToolNotFoundException e) {
            Assert.isTrue(e.getMessage().contains('NonExistentClassName_XYZ'));
        }
    }

    @IsTest
    static void testToDefinitionStructure() {
        FC_Tool tool = FC_Tool.fromMCP(new FC_SampleSOQLTool());
        Map<String, Object> def = tool.toDefinition();

        Assert.areEqual('QueryRecords', def.get('name'));
        Assert.isNotNull(def.get('description'));

        Map<String, Object> paramsSchema = (Map<String, Object>) def.get('parameters');
        Assert.areEqual('object', paramsSchema.get('type'));

        Map<String, Object> props = (Map<String, Object>) paramsSchema.get('properties');
        Assert.isTrue(props.containsKey('query'));

        List<Object> required = (List<Object>) paramsSchema.get('required');
        Assert.isTrue(required.contains('query'));
    }

    @IsTest
    static void testExecuteReturnsJSON() {
        FC_Tool tool = FC_Tool.fromMCP(new FC_SampleSOQLTool());
        String result = tool.execute(new Map<String, Object>{ 'query' => 'SELECT Id FROM Account LIMIT 1' });

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isNotNull(parsed.get('success'));
    }

    @IsTest
    static void testExecuteHandlesNullParams() {
        FC_Tool tool = FC_Tool.fromMCP(new FC_SampleSOQLTool());
        // FC_SampleSOQLTool will return error JSON (missing "query") — should not throw
        String result = tool.execute(null);
        Assert.isNotNull(result);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) parsed.get('success'));
    }
}
