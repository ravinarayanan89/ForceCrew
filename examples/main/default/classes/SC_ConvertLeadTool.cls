/**
 * SC_ConvertLeadTool - Converts a qualified Lead into Account, Contact, and Opportunity.
 *
 * Uses Database.convertLead() with the standard Salesforce lead conversion API.
 * Call this only when the customer has clearly expressed interest and is ready to move
 * to the Opportunity stage.
 *
 * @group SalesCycle
 */
public with sharing class SC_ConvertLeadTool implements FC_IMCPTool {

    public String getName() {
        return 'ConvertLead';
    }

    public String getDescription() {
        return 'Converts a qualified Lead into a Salesforce Account, Contact, and Opportunity. '
            + 'Only call this when the customer has expressed clear purchase intent. '
            + 'Returns the new Account Id, Contact Id, and Opportunity Id.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('leadId', FC_ToolParameter.TYPE_STRING)
                .description('The Salesforce Lead Id to convert')
                .required()
                .build(),
            new FC_ToolParameter.Builder('opportunityName', FC_ToolParameter.TYPE_STRING)
                .description('Name for the new Opportunity (e.g. "Acme Corp - AI Platform")')
                .required()
                .build(),
            new FC_ToolParameter.Builder('createOpportunity', FC_ToolParameter.TYPE_BOOLEAN)
                .description('Whether to create an Opportunity during conversion. Default: true')
                .defaultValue(true)
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String  leadId          = (String)  params.get('leadId');
            String  opportunityName = (String)  params.get('opportunityName');
            Boolean createOpp       = params.containsKey('createOpportunity')
                ? Boolean.valueOf(String.valueOf(params.get('createOpportunity')))
                : true;

            if (String.isBlank(leadId)) {
                return error('leadId is required');
            }
            if (String.isBlank(opportunityName) && createOpp) {
                return error('opportunityName is required when createOpportunity is true');
            }

            // Verify the lead exists and is not already converted
            List<Lead> leads = [SELECT Id, IsConverted, Status FROM Lead WHERE Id = :leadId LIMIT 1];
            if (leads.isEmpty()) {
                return error('Lead not found: ' + leadId);
            }
            if (leads[0].IsConverted) {
                // Already converted — return existing IDs
                Lead l = [
                    SELECT ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId
                    FROM Lead WHERE Id = :leadId LIMIT 1
                ];
                return JSON.serialize(new Map<String, Object>{
                    'success'       => true,
                    'alreadyConverted' => true,
                    'accountId'     => l.ConvertedAccountId,
                    'contactId'     => l.ConvertedContactId,
                    'opportunityId' => l.ConvertedOpportunityId
                });
            }

            // Get the first "Converted" lead status
            List<LeadStatus> convertedStatuses = [
                SELECT MasterLabel FROM LeadStatus
                WHERE IsConverted = true
                ORDER BY SortOrder ASC NULLS LAST
                LIMIT 1
            ];
            if (convertedStatuses.isEmpty()) {
                return error('No converted lead status found in org. Please configure a converted Lead Status.');
            }

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            lc.setConvertedStatus(convertedStatuses[0].MasterLabel);
            lc.setDoNotCreateOpportunity(!createOpp);
            if (createOpp && String.isNotBlank(opportunityName)) {
                lc.setOpportunityName(opportunityName);
            }

            Database.LeadConvertResult lcr = Database.convertLead(lc);

            if (!lcr.isSuccess()) {
                List<String> errors = new List<String>();
                for (Database.Error e : lcr.getErrors()) {
                    errors.add(e.getMessage());
                }
                return error('Lead conversion failed: ' + String.join(errors, '; '));
            }

            return JSON.serialize(new Map<String, Object>{
                'success'       => true,
                'accountId'     => lcr.getAccountId(),
                'contactId'     => lcr.getContactId(),
                'opportunityId' => lcr.getOpportunityId(),
                'message'       => 'Lead successfully converted. Account, Contact, and Opportunity created.'
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
