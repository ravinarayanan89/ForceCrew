/**
 * SC_InboundEmailHandler - Salesforce Email Service handler for the AI sales cycle.
 *
 * When a customer replies to any agent email, Salesforce routes it here via the
 * Email Service address. This class:
 *   1. Matches the sender to a Lead, Contact, or Opportunity by email address
 *   2. Determines the current sales stage from the most recent conversation record
 *   3. Logs the customer message as an Inbound SC_ConversationMessage__c
 *   4. Delegates to the appropriate crew phase handler
 *
 * Setup (one-time):
 *   Setup → Email Services → New → Apex Class: SC_InboundEmailHandler
 *   → Accept Email From: all (or restrict to customer domains)
 *   → Copy the generated email address — this is what agents put in the From/Reply-To field
 *
 * The SC_LogEmailTool must include this Email Service address as the Reply-To so
 * customer replies are routed here automatically.
 *
 * @group SalesCycle
 */
global with sharing class SC_InboundEmailHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = true;

        try {
            String fromAddress  = email.fromAddress?.toLowerCase();
            String subject      = email.subject ?? '(no subject)';
            String body         = getBody(email);

            if (String.isBlank(fromAddress) || String.isBlank(body)) {
                FC_Logger.warn('SC_InboundEmailHandler', 'Ignored: missing from address or body');
                return result;
            }

            // ── 1. Resolve sender to Salesforce records ────────────────────
            EmailContext ctx = resolveContext(fromAddress);

            if (!ctx.found) {
                // Unknown sender — create a Lead so no reply falls through the cracks
                FC_Logger.info('SC_InboundEmailHandler',
                    'Unknown sender ' + fromAddress + ' — creating new Lead');
                ctx = createLeadFromEmail(email, fromAddress);
            }

            // ── 2. Log the inbound message ────────────────────────────────
            SC_ConversationMessage__c msg = new SC_ConversationMessage__c(
                Direction__c  = 'Inbound',
                Stage__c      = ctx.stage,
                Subject__c    = subject.abbreviate(255),
                Body__c       = body,
                FromEmail__c  = fromAddress,
                ToEmail__c    = 'sales-agent@forcecrew.ai',
                AgentName__c  = 'Customer',
                SentDate__c   = DateTime.now()
            );
            if (ctx.leadId != null)        msg.LeadId__c        = ctx.leadId;
            if (ctx.contactId != null)     msg.ContactId__c     = ctx.contactId;
            if (ctx.opportunityId != null) msg.OpportunityId__c = ctx.opportunityId;
            insert msg;

            FC_Logger.info('SC_InboundEmailHandler',
                'Logged inbound email from ' + fromAddress
                + ' | stage=' + ctx.stage
                + ' | leadId=' + ctx.leadId
                + ' | oppId=' + ctx.opportunityId);

            // ── 3. Dispatch to the appropriate crew ────────────────────────
            dispatch(ctx, body);

        } catch (Exception e) {
            FC_Logger.error('SC_InboundEmailHandler', 'Error processing email: ' + e.getMessage());
            // Return success=true so Salesforce does not bounce the email back
        }

        return result;
    }

    // ─── Context Resolution ────────────────────────────────────────────────────

    /**
     * Matches the sender email address to Lead, Contact, and Opportunity.
     * Also determines the current sales stage from conversation history.
     */
    private EmailContext resolveContext(String fromAddress) {
        EmailContext ctx = new EmailContext();

        // Try Contact first (post-conversion)
        List<Contact> contacts = [
            SELECT Id, AccountId FROM Contact
            WHERE Email = :fromAddress AND IsDeleted = false
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!contacts.isEmpty()) {
            ctx.contactId = contacts[0].Id;
            ctx.found     = true;

            // Find the most recent open Opportunity for this account
            List<Opportunity> opps = [
                SELECT Id, StageName FROM Opportunity
                WHERE AccountId = :contacts[0].AccountId
                  AND IsClosed = false
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!opps.isEmpty()) {
                ctx.opportunityId = opps[0].Id;
            }
        }

        // Try Lead (pre-conversion)
        List<Lead> leads = [
            SELECT Id, IsConverted, ConvertedOpportunityId FROM Lead
            WHERE Email = :fromAddress AND IsConverted = false AND IsDeleted = false
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!leads.isEmpty()) {
            ctx.leadId = leads[0].Id;
            ctx.found  = true;
        }

        // Determine stage from most recent conversation record
        ctx.stage = resolveStage(ctx.leadId, ctx.contactId, ctx.opportunityId);
        return ctx;
    }

    /**
     * Reads the most recent SC_ConversationMessage__c to determine the active stage.
     * Defaults to 'Lead' if no prior conversation exists.
     */
    private String resolveStage(Id leadId, Id contactId, Id opportunityId) {
        List<String> conditions = new List<String>();
        if (leadId != null)        conditions.add('LeadId__c = \'' + leadId + '\'');
        if (contactId != null)     conditions.add('ContactId__c = \'' + contactId + '\'');
        if (opportunityId != null) conditions.add('OpportunityId__c = \'' + opportunityId + '\'');

        if (conditions.isEmpty()) return 'Lead';

        String soql = 'SELECT Stage__c FROM SC_ConversationMessage__c WHERE ('
            + String.join(conditions, ' OR ')
            + ') ORDER BY SentDate__c DESC NULLS LAST LIMIT 1';

        List<SC_ConversationMessage__c> recent = Database.query(soql);
        return recent.isEmpty() ? 'Lead' : recent[0].Stage__c;
    }

    // ─── Crew Dispatch ─────────────────────────────────────────────────────────

    /**
     * Routes the inbound email to the correct crew phase based on current stage.
     * Runs async (Queueable) to avoid governor limit issues with long LLM calls.
     */
    private void dispatch(EmailContext ctx, String body) {
        System.enqueueJob(new SC_InboundEmailDispatchQueueable(ctx, body));
    }

    // ─── Lead Creation ─────────────────────────────────────────────────────────

    private EmailContext createLeadFromEmail(Messaging.InboundEmail email, String fromAddress) {
        String[] nameParts = (email.fromName ?? '').split(' ');
        Lead newLead = new Lead(
            FirstName  = nameParts.size() > 1 ? nameParts[0] : 'Unknown',
            LastName   = nameParts.size() > 1 ? nameParts[nameParts.size() - 1] : (email.fromName ?? 'Unknown'),
            Email      = fromAddress,
            Company    = extractDomain(fromAddress),
            LeadSource = 'Email',
            Status     = 'Open - Not Contacted',
            Description = 'Auto-created from inbound email.\n\nOriginal message:\n' + getBody(email)
        );
        insert newLead;

        EmailContext ctx  = new EmailContext();
        ctx.found         = true;
        ctx.leadId        = newLead.Id;
        ctx.stage         = 'Lead';
        return ctx;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private String getBody(Messaging.InboundEmail email) {
        if (String.isNotBlank(email.plainTextBody)) return email.plainTextBody.trim();
        if (String.isNotBlank(email.htmlBody))      return email.htmlBody.stripHtmlTags().trim();
        return '';
    }

    private String extractDomain(String emailAddr) {
        if (String.isBlank(emailAddr) || !emailAddr.contains('@')) return 'Unknown Company';
        String domain = emailAddr.substringAfter('@').substringBefore('.');
        return domain.substring(0, 1).toUpperCase() + domain.substring(1) + ' (auto)';
    }

    // ─── Inner Context DTO ────────────────────────────────────────────────────

    public class EmailContext {
        public Boolean found        = false;
        public String  stage        = 'Lead';
        public Id      leadId;
        public Id      contactId;
        public Id      opportunityId;
    }
}
