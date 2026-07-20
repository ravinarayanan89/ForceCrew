/**
 * SC_DMLTool - Single dynamic DML tool for any Salesforce object.
 *
 * Handles insert and update on any SObject by name. The agent provides the object
 * API name and a JSON map of field API names to values. Type coercion (String →
 * Decimal, Date, Boolean, Id, etc.) is handled automatically using field describe.
 *
 * Replaces all single-object DML wrapper tools (SC_UpdateOpportunityTool, etc.).
 * Pair with FC_SampleSOQLTool (reads) and complex custom tools (ConvertLead,
 * CreateQuote, CreateOrder, etc.) for complete CRM coverage.
 *
 * Tool name agents must use: DMLRecord
 *
 * Examples:
 *   Update Opportunity stage:
 *     { "operation": "update", "objectApiName": "Opportunity",
 *       "recordId": "006...", "fields": {"StageName": "Needs Analysis"} }
 *
 *   Insert a Conversation Message:
 *     { "operation": "insert", "objectApiName": "SC_ConversationMessage__c",
 *       "fields": {"Direction__c": "Outbound", "Stage__c": "Lead", "Body__c": "Hi!"} }
 *
 * @group SalesCycle
 */
public with sharing class SC_DMLTool implements FC_IMCPTool {

    public String getName() {
        return 'DMLRecord';
    }

    public String getDescription() {
        return 'Inserts or updates any Salesforce record by object API name. '
            + 'Provide the operation (insert or update), the object API name '
            + '(e.g. Opportunity, Lead, SC_ConversationMessage__c), '
            + 'a recordId for updates, and a JSON object of field API names to values. '
            + 'Field types are coerced automatically. '
            + 'Use QueryRecords (FC_SampleSOQLTool) to read data first, then DMLRecord to write.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('operation', FC_ToolParameter.TYPE_STRING)
                .description('DML operation: "insert" or "update"')
                .required()
                .build(),
            new FC_ToolParameter.Builder('objectApiName', FC_ToolParameter.TYPE_STRING)
                .description('Salesforce object API name (e.g. Opportunity, Lead, Contact, SC_ConversationMessage__c)')
                .required()
                .build(),
            new FC_ToolParameter.Builder('fields', FC_ToolParameter.TYPE_STRING)
                .description('JSON object of field API name → value pairs. '
                    + 'Example: {"StageName": "Closed Won", "CloseDate": "2025-12-31", "Amount": 50000}')
                .required()
                .build(),
            new FC_ToolParameter.Builder('recordId', FC_ToolParameter.TYPE_STRING)
                .description('Record Id — required for update, omit for insert')
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String operation    = ((String) params.get('operation'))?.toLowerCase();
            String objectName   = (String) params.get('objectApiName');
            String fieldsStr    = (String) params.get('fields');
            String recordIdStr  = (String) params.get('recordId');

            if (String.isBlank(operation))  return error('operation is required (insert or update)');
            if (String.isBlank(objectName)) return error('objectApiName is required');
            if (String.isBlank(fieldsStr))  return error('fields (JSON) is required');
            if (!new Set<String>{'insert', 'update'}.contains(operation)) {
                return error('operation must be "insert" or "update"');
            }
            if (operation == 'update' && String.isBlank(recordIdStr)) {
                return error('recordId is required for update');
            }

            // Validate object
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectName);
            if (sot == null) {
                return error('Unknown object API name: "' + objectName
                    + '". Use the exact API name including __c suffix for custom objects.');
            }
            Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();

            // Parse field values
            Map<String, Object> fieldValues;
            try {
                fieldValues = (Map<String, Object>) JSON.deserializeUntyped(fieldsStr);
            } catch (Exception e) {
                return error('Invalid JSON in fields parameter: ' + e.getMessage());
            }

            SObject record = sot.newSObject();

            for (String fieldName : fieldValues.keySet()) {
                Object rawValue = fieldValues.get(fieldName);
                if (rawValue == null) continue;

                Schema.SObjectField fieldToken = fieldMap.get(fieldName.toLowerCase());
                if (fieldToken == null) {
                    return error('Field "' + fieldName + '" does not exist on ' + objectName
                        + '. Use the exact API field name including __c for custom fields.');
                }

                record.put(fieldName, coerce(rawValue, fieldToken.getDescribe().getType()));
            }

            if (operation == 'update') {
                record.put('Id', (Id) recordIdStr);
                update record;
            } else {
                insert record;
            }

            return JSON.serialize(new Map<String, Object>{
                'success'   => true,
                'operation' => operation,
                'object'    => objectName,
                'recordId'  => String.valueOf(record.Id),
                'message'   => operation + ' on ' + objectName + ' succeeded. Id: ' + record.Id
            });

        } catch (DmlException e) {
            return error('DML failed: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    // ─── Type Coercion ────────────────────────────────────────────────────────

    private Object coerce(Object rawValue, Schema.DisplayType dtype) {
        if (rawValue == null) return null;
        String strVal = String.valueOf(rawValue);

        switch on dtype {
            when CURRENCY, DOUBLE, PERCENT {
                return Decimal.valueOf(strVal);
            }
            when INTEGER {
                return Integer.valueOf(strVal);
            }
            when DATE {
                return Date.valueOf(strVal);
            }
            when DATETIME {
                return DateTime.valueOf(strVal);
            }
            when BOOLEAN {
                return Boolean.valueOf(strVal);
            }
            when REFERENCE {
                return String.isBlank(strVal) ? null : (Id) strVal;
            }
            when else {
                return strVal;
            }
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
