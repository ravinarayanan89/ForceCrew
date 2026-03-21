/**
 * FC_SampleDescribeTool - A sample FC_IMCPTool that returns field metadata for a Salesforce object.
 *
 * Agents use this tool to discover what fields are available on an object
 * before constructing SOQL queries or describing data structure.
 *
 *   FC_Tool tool = FC_Tool.fromMCP(new FC_SampleDescribeTool());
 *
 * @group ForceCrew
 */
public with sharing class FC_SampleDescribeTool implements FC_IMCPTool {

    // ─── FC_IMCPTool ──────────────────────────────────────────────────────────

    public String getName() {
        return 'DescribeObject';
    }

    public String getDescription() {
        return 'Returns the field names, labels, and types available on a Salesforce object. '
            + 'Use this before querying to confirm which fields exist and are accessible. '
            + 'Required parameter: the API name of the SObject (e.g., Account, Contact, Opportunity).';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('objectType', FC_ToolParameter.TYPE_STRING)
                .description(
                    'The API name of the Salesforce object to describe. '
                    + 'Examples: Account, Contact, Opportunity, Lead, Case'
                )
                .required()
                .build()
        };
    }

    // ─── FC_ITool ─────────────────────────────────────────────────────────────

    public String execute(Map<String, Object> params) {
        String objectType = (String) params.get('objectType');

        if (String.isBlank(objectType)) {
            return errorResult('Parameter "objectType" is required.');
        }

        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectType);
            if (sObjType == null) {
                return errorResult('Object type not found: "' + objectType
                    + '". Use the API name (e.g., Account, not Accounts).');
            }

            Schema.DescribeSObjectResult describe = sObjType.getDescribe();
            Map<String, Schema.SObjectField> fieldsMap = describe.fields.getMap();

            List<Map<String, Object>> fields = new List<Map<String, Object>>();
            for (String fieldName : fieldsMap.keySet()) {
                Schema.DescribeFieldResult field = fieldsMap.get(fieldName).getDescribe();
                if (!field.isAccessible()) continue;
                fields.add(new Map<String, Object>{
                    'name'     => field.getName(),
                    'label'    => field.getLabel(),
                    'type'     => String.valueOf(field.getType()),
                    'required' => (!field.isNillable() && field.isCreateable())
                });
            }

            return JSON.serialize(new Map<String, Object>{
                'success'     => true,
                'objectType'  => objectType,
                'label'       => describe.getLabel(),
                'fieldCount'  => fields.size(),
                'fields'      => fields
            });

        } catch (Exception e) {
            return errorResult(e.getMessage());
        }
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    private String errorResult(String message) {
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'error'   => message
        });
    }
}
