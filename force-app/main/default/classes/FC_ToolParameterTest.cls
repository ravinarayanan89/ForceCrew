/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_ToolParameterTest {

    @IsTest
    static void testBuilderCreatesParameter() {
        FC_ToolParameter param = new FC_ToolParameter.Builder('query', FC_ToolParameter.TYPE_STRING)
            .description('A SOQL query')
            .required()
            .build();

        Assert.areEqual('query',                    param.name);
        Assert.areEqual(FC_ToolParameter.TYPE_STRING, param.paramType);
        Assert.areEqual('A SOQL query',             param.description);
        Assert.isTrue(param.required);
        Assert.isNull(param.defaultValue);
    }

    @IsTest
    static void testBuilderWithDefaultValue() {
        FC_ToolParameter param = new FC_ToolParameter.Builder('limit', FC_ToolParameter.TYPE_INTEGER)
            .defaultValue(10)
            .build();

        Assert.isFalse(param.required);
        Assert.areEqual(10, param.defaultValue);
    }

    @IsTest
    static void testBlankNameThrows() {
        try {
            new FC_ToolParameter.Builder('', FC_ToolParameter.TYPE_STRING).build();
            Assert.fail('Expected ConfigurationException');
        } catch (FC_Exception.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('name'));
        }
    }

    @IsTest
    static void testToSchemaBasic() {
        FC_ToolParameter param = new FC_ToolParameter.Builder('limit', FC_ToolParameter.TYPE_INTEGER)
            .description('Max rows')
            .build();

        Map<String, Object> schema = param.toSchema();
        Assert.areEqual('integer', schema.get('type'));
        Assert.areEqual('Max rows', schema.get('description'));
        Assert.isFalse(schema.containsKey('default'));
    }

    @IsTest
    static void testToSchemaIncludesDefault() {
        FC_ToolParameter param = new FC_ToolParameter.Builder('limit', FC_ToolParameter.TYPE_INTEGER)
            .defaultValue(20)
            .build();

        Map<String, Object> schema = param.toSchema();
        Assert.areEqual(20, schema.get('default'));
    }

    @IsTest
    static void testDefaultsToStringType() {
        FC_ToolParameter param = new FC_ToolParameter.Builder('name', null).build();
        Assert.areEqual(FC_ToolParameter.TYPE_STRING, param.paramType);
    }
}
