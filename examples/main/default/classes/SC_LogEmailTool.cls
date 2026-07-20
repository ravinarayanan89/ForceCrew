/**
 * SC_LogEmailTool - Logs an outbound agent email to the SC_ConversationMessage__c object
 * AND sends the actual Salesforce email with Reply-To set to the Email Service address.
 *
 * Every email the agent "sends" is:
 *   1. Persisted as SC_ConversationMessage__c (Direction = Outbound)
 *   2. Delivered via Messaging.SingleEmailMessage with Reply-To = EMAIL_SERVICE_ADDRESS
 *      so customer replies automatically route to SC_InboundEmailHandler.
 *
 * Setup: replace EMAIL_SERVICE_ADDRESS with your actual Email Services address from
 *   Setup → Email Services → <your service> → Email Addresses.
 *
 * @group SalesCycle
 */
public with sharing class SC_LogEmailTool implements FC_IMCPTool {

    // Replace with your Email Services address after running Setup → Email Services
    // Format: <serviceName>@<orgId>.inbound.salesforce.com
    @TestVisible
    private static String EMAIL_SERVICE_ADDRESS {
        get {
            // Read from Custom Metadata or Custom Setting if available; fall back to org-wide default
            List<SC_SalesCycleSettings__c> settings = [
                SELECT EmailServiceAddress__c FROM SC_SalesCycleSettings__c LIMIT 1
            ];
            if (!settings.isEmpty() && String.isNotBlank(settings[0].EmailServiceAddress__c)) {
                return settings[0].EmailServiceAddress__c;
            }
            return null; // email not configured — log only, don't send
        }
    }

    public String getName() {
        return 'LogOutboundEmail';
    }

    public String getDescription() {
        return 'Logs an outbound email from the AI sales agent to the conversation history. '
            + 'Call this after composing every email to the customer — it persists the message '
            + 'and makes it visible on the Lead, Contact, or Opportunity record. '
            + 'Returns the created message Id.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('stage', FC_ToolParameter.TYPE_STRING)
                .description('Current sales stage. Must be one of: Lead, Opportunity, Quote, Payment, Order')
                .required()
                .build(),
            new FC_ToolParameter.Builder('subject', FC_ToolParameter.TYPE_STRING)
                .description('Email subject line')
                .required()
                .build(),
            new FC_ToolParameter.Builder('body', FC_ToolParameter.TYPE_STRING)
                .description('Full email body text')
                .required()
                .build(),
            new FC_ToolParameter.Builder('toEmail', FC_ToolParameter.TYPE_STRING)
                .description('Recipient email address (customer email)')
                .required()
                .build(),
            new FC_ToolParameter.Builder('agentName', FC_ToolParameter.TYPE_STRING)
                .description('Name of the agent sending this email (e.g. "Lead Outreach Agent")')
                .required()
                .build(),
            new FC_ToolParameter.Builder('leadId', FC_ToolParameter.TYPE_STRING)
                .description('Lead Id — provide when stage is Lead')
                .build(),
            new FC_ToolParameter.Builder('contactId', FC_ToolParameter.TYPE_STRING)
                .description('Contact Id — provide when stage is Opportunity, Quote, Payment, or Order')
                .build(),
            new FC_ToolParameter.Builder('opportunityId', FC_ToolParameter.TYPE_STRING)
                .description('Opportunity Id — provide when stage is Opportunity, Quote, Payment, or Order')
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String stage        = (String) params.get('stage');
            String subject      = (String) params.get('subject');
            String body         = (String) params.get('body');
            String toEmail      = (String) params.get('toEmail');
            String agentName    = (String) params.get('agentName');
            String leadIdStr    = (String) params.get('leadId');
            String contactIdStr = (String) params.get('contactId');
            String oppIdStr     = (String) params.get('opportunityId');

            if (String.isBlank(stage) || String.isBlank(subject) || String.isBlank(body)) {
                return error('stage, subject, and body are required');
            }

            SC_ConversationMessage__c msg = new SC_ConversationMessage__c(
                Stage__c      = stage,
                Direction__c  = 'Outbound',
                Subject__c    = subject,
                Body__c       = body,
                ToEmail__c    = toEmail,
                FromEmail__c  = 'sales-agent@forcecrew.ai',
                AgentName__c  = agentName,
                SentDate__c   = DateTime.now()
            );

            if (String.isNotBlank(leadIdStr))    msg.LeadId__c        = (Id) leadIdStr;
            if (String.isNotBlank(contactIdStr)) msg.ContactId__c     = (Id) contactIdStr;
            if (String.isNotBlank(oppIdStr))     msg.OpportunityId__c = (Id) oppIdStr;

            insert msg;

            // ── Send actual Salesforce email (if address is configured) ────
            Boolean emailSent = false;
            if (String.isNotBlank(toEmail) && String.isNotBlank(EMAIL_SERVICE_ADDRESS)) {
                try {
                    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                    mail.setToAddresses(new List<String>{ toEmail });
                    mail.setReplyTo(EMAIL_SERVICE_ADDRESS); // customer replies route here
                    mail.setSenderDisplayName(agentName ?? 'ForceCrew Sales');
                    mail.setSubject(subject);
                    mail.setPlainTextBody(body);
                    mail.setSaveAsActivity(false);
                    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
                    emailSent = true;
                } catch (Exception emailEx) {
                    // Log but don't fail — the conversation record is the source of truth
                    FC_Logger.warn('SC_LogEmailTool',
                        'Salesforce email send failed (record still logged): ' + emailEx.getMessage());
                }
            }

            return JSON.serialize(new Map<String, Object>{
                'success'      => true,
                'messageId'    => msg.Id,
                'emailSent'    => emailSent,
                'replyToSet'   => emailSent,
                'message'      => 'Email logged' + (emailSent ? ' and delivered' : ' (delivery pending Email Service config)')
                    + '. Subject: "' + subject + '"'
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
