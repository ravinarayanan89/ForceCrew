/**
 * SC_SalesCycleCrew - Master orchestrator for the end-to-end AI sales cycle demo.
 *
 * Coordinates five specialised crews across the full sales lifecycle:
 *
 *   Phase 1  LEAD OUTREACH       → SC_LeadCrew.outreach()
 *   Phase 2  LEAD RESPONSE       → SC_LeadCrew.handleReply()  (lead converted here)
 *   Phase 3  OPPORTUNITY         → SC_OpportunityCrew.run()   (products added)
 *   Phase 4a QUOTE               → SC_QuoteCrew.createAndSend()
 *   Phase 4b NEGOTIATION         → SC_QuoteCrew.negotiate()
 *   Phase 5  PAYMENT             → SC_PaymentCrew.run()       (PayPal invoice sent)
 *   Phase 6  ORDER               → SC_OrderCrew.run()         (order created + confirmed)
 *
 * Customer emails are INBOUND (SC_ConversationMessage__c records with Direction=Inbound).
 * Agent emails are OUTBOUND (created by SC_LogEmailTool via the crew).
 *
 * ─── Demo Runner ─────────────────────────────────────────────────────────────
 * Run the full cycle from Anonymous Apex:
 *
 *   // 1. Create a test lead (or use existing)
 *   Id leadId = [SELECT Id FROM Lead WHERE IsConverted = false LIMIT 1].Id;
 *
 *   // Phase 1: Agent sends first outreach email
 *   SC_SalesCycleCrew.PhaseResult p1 = SC_SalesCycleCrew.startLeadOutreach(leadId);
 *   System.debug('Agent email: ' + p1.agentOutput);
 *
 *   // Phase 2: Customer replies and agent converts lead
 *   SC_SalesCycleCrew.logCustomerReply(leadId, null, 'Lead',
 *       'Hi! We\'re very interested in your AI platform. Can we discuss pricing?');
 *   SC_SalesCycleCrew.PhaseResult p2 = SC_SalesCycleCrew.handleLeadReply(leadId,
 *       'Hi! We\'re very interested in your AI platform. Can we discuss pricing?');
 *   System.debug('Opp: ' + p2.opportunityId);
 *
 *   // Phase 3: Customer shares needs, products added
 *   SC_SalesCycleCrew.logCustomerReply(null, p2.opportunityId, 'Opportunity',
 *       'We need predictive analytics and CRM integration for 500 users. Budget around $50K.');
 *   SC_SalesCycleCrew.PhaseResult p3 = SC_SalesCycleCrew.startOpportunityPhase(p2.opportunityId,
 *       'We need predictive analytics and CRM integration for 500 users. Budget around $50K.');
 *
 *   // Phase 4a: Agent sends formal quote
 *   SC_SalesCycleCrew.PhaseResult p4 = SC_SalesCycleCrew.startQuotePhase(p2.opportunityId);
 *   System.debug('Quote: ' + p4.quoteId);
 *
 *   // Phase 4b: Customer negotiates
 *   SC_SalesCycleCrew.logCustomerReply(null, p2.opportunityId, 'Quote',
 *       'The quote looks good. Can you do 10% off to fit our budget?');
 *   SC_SalesCycleCrew.PhaseResult p4b = SC_SalesCycleCrew.negotiateQuote(p2.opportunityId,
 *       'The quote looks good. Can you do 10% off to fit our budget?');
 *
 *   // Phase 5: Payment — PayPal invoice sent
 *   SC_SalesCycleCrew.PhaseResult p5 = SC_SalesCycleCrew.startPaymentPhase(p2.opportunityId);
 *   System.debug('Payment link: ' + p5.paymentLink);
 *
 *   // Simulate payment received (triggers Closed Won + creates order)
 *   SC_SalesCycleCrew.markPaymentReceived(p5.invoiceId);
 *
 *   // Phase 6: Order created + confirmation sent
 *   SC_SalesCycleCrew.PhaseResult p6 = SC_SalesCycleCrew.startOrderPhase(p2.opportunityId);
 *   System.debug('Order: ' + p6.orderNumber);
 *
 * @group SalesCycle
 */
public with sharing class SC_SalesCycleCrew {

    // ─── Phase Result DTO ─────────────────────────────────────────────────────

    public class PhaseResult {
        @AuraEnabled public Boolean success       { get; set; }
        @AuraEnabled public String  phase         { get; set; }
        @AuraEnabled public String  agentOutput   { get; set; }
        @AuraEnabled public String  errorMessage  { get; set; }

        // Record IDs created/found during this phase
        @AuraEnabled public Id      leadId        { get; set; }
        @AuraEnabled public Id      accountId     { get; set; }
        @AuraEnabled public Id      contactId     { get; set; }
        @AuraEnabled public Id      opportunityId { get; set; }
        @AuraEnabled public String  quoteId       { get; set; }
        @AuraEnabled public String  invoiceId     { get; set; }
        @AuraEnabled public String  paymentLink   { get; set; }
        @AuraEnabled public String  orderId       { get; set; }
        @AuraEnabled public String  orderNumber   { get; set; }

    }

    // ─── Phase Result Factories ───────────────────────────────────────────────
    // (Inner classes cannot have static methods in Apex — factories live here.)

    private static PhaseResult makeOk(String phase, String output) {
        PhaseResult r = new PhaseResult();
        r.success     = true;
        r.phase       = phase;
        r.agentOutput = output;
        return r;
    }

    private static PhaseResult makeFail(String phase, String msg) {
        PhaseResult r = new PhaseResult();
        r.success      = false;
        r.phase        = phase;
        r.errorMessage = msg;
        return r;
    }

    // ─── Phase 1: Lead Outreach ───────────────────────────────────────────────

    /**
     * Agent researches the lead, qualifies it, and sends a personalised first-touch email.
     */
    public static PhaseResult startLeadOutreach(Id leadId) {
        SC_LeadCrew.Result r = SC_LeadCrew.outreach(leadId);
        if (!r.success) return makeFail('Lead Outreach', r.errorMessage);

        PhaseResult result = makeOk('Lead Outreach', r.agentEmail);
        result.leadId = leadId;
        return result;
    }

    // ─── Phase 2: Handle Lead Reply ───────────────────────────────────────────

    /**
     * Agent reads the conversation, responds or converts the lead.
     * After this phase, query the Lead to get converted Account/Contact/Opportunity IDs.
     */
    public static PhaseResult handleLeadReply(Id leadId, String customerMessage) {
        SC_LeadCrew.Result r = SC_LeadCrew.handleReply(leadId, customerMessage);
        if (!r.success) return makeFail('Lead Reply', r.errorMessage);

        PhaseResult result = makeOk('Lead Reply', r.agentEmail ?? r.conversionSummary);
        result.leadId = leadId;

        // Read converted IDs from Salesforce (the agent may have called ConvertLead)
        Lead converted = [
            SELECT IsConverted, ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId
            FROM Lead WHERE Id = :leadId LIMIT 1
        ];
        if (converted.IsConverted) {
            result.accountId     = converted.ConvertedAccountId;
            result.contactId     = converted.ConvertedContactId;
            result.opportunityId = converted.ConvertedOpportunityId;
        }
        return result;
    }

    // ─── Phase 3: Opportunity / Products ─────────────────────────────────────

    /**
     * Agent discovers customer needs from the message, searches products, adds them to the Opp,
     * and sends a follow-up email.
     */
    public static PhaseResult startOpportunityPhase(Id opportunityId, String customerMessage) {
        SC_OpportunityCrew.Result r = SC_OpportunityCrew.run(opportunityId, customerMessage);
        if (!r.success) return makeFail('Opportunity', r.errorMessage);

        PhaseResult result = makeOk('Opportunity', r.agentEmail);
        result.opportunityId = opportunityId;
        return result;
    }

    // ─── Phase 4a: Create and Send Quote ─────────────────────────────────────

    /**
     * Agent creates a formal Quote from the Opportunity products and emails it to the customer.
     */
    public static PhaseResult startQuotePhase(Id opportunityId) {
        SC_QuoteCrew.Result r = SC_QuoteCrew.createAndSend(opportunityId);
        if (!r.success) return makeFail('Quote', r.errorMessage);

        PhaseResult result = makeOk('Quote', r.agentEmail);
        result.opportunityId = opportunityId;
        result.quoteId       = r.quoteId;

        // Refresh quoteId from Salesforce if agent-extracted value was null
        if (String.isBlank(result.quoteId)) {
            List<Quote> quotes = [
                SELECT Id FROM Quote WHERE OpportunityId = :opportunityId
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!quotes.isEmpty()) result.quoteId = quotes[0].Id;
        }
        return result;
    }

    // ─── Phase 4b: Negotiate Quote ────────────────────────────────────────────

    /**
     * Agent handles a customer discount request, applies an approved discount, and resends the quote.
     */
    public static PhaseResult negotiateQuote(Id opportunityId, String customerMessage) {
        SC_QuoteCrew.Result r = SC_QuoteCrew.negotiate(opportunityId, customerMessage);
        if (!r.success) return makeFail('Negotiation', r.errorMessage);

        PhaseResult result = makeOk('Negotiation', r.agentEmail);
        result.opportunityId = opportunityId;
        result.quoteId       = r.quoteId;
        return result;
    }

    // ─── Phase 5: Payment ─────────────────────────────────────────────────────

    /**
     * Agent creates a PayPal invoice and emails the payment link to the customer.
     */
    public static PhaseResult startPaymentPhase(Id opportunityId) {
        SC_PaymentCrew.Result r = SC_PaymentCrew.run(opportunityId);
        if (!r.success) return makeFail('Payment', r.errorMessage);

        PhaseResult result = makeOk('Payment', r.agentEmail);
        result.opportunityId = opportunityId;
        result.invoiceId     = r.invoiceId;
        result.paymentLink   = r.paymentLink;

        // Refresh invoiceId from Salesforce if needed
        if (String.isBlank(result.invoiceId)) {
            List<SC_PayPalInvoice__c> invoices = [
                SELECT Id, PaymentLink__c FROM SC_PayPalInvoice__c
                WHERE OpportunityId__c = :opportunityId
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!invoices.isEmpty()) {
                result.invoiceId   = invoices[0].Id;
                result.paymentLink = invoices[0].PaymentLink__c;
            }
        }
        return result;
    }

    // ─── Phase 5b: Mark Payment Received ─────────────────────────────────────

    /**
     * Simulates payment confirmation: marks the invoice Paid and closes the Opportunity as Won.
     * In production, trigger this from a PayPal webhook.
     */
    public static PhaseResult markPaymentReceived(Id invoiceId) {
        if (invoiceId == null) return makeFail('Payment Confirmation', 'invoiceId is required');

        SC_MarkPaymentReceivedTool tool = new SC_MarkPaymentReceivedTool();
        String result = tool.execute(new Map<String, Object>{ 'invoiceId' => invoiceId });

        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        } catch (Exception e) {
            return makeFail('Payment Confirmation', 'Failed to parse tool response: ' + e.getMessage());
        }

        if (parsed.get('success') == true) {
            PhaseResult pr = makeOk('Payment Confirmation',
                'Payment received. Opportunity closed as Won.');
            pr.invoiceId     = invoiceId;
            pr.opportunityId = (Id) parsed.get('opportunityId');
            return pr;
        } else {
            return makeFail('Payment Confirmation', (String) parsed.get('error'));
        }
    }

    // ─── Phase 6: Order ───────────────────────────────────────────────────────

    /**
     * Agent creates a Salesforce Order from the Closed Won Opportunity and sends a confirmation email.
     */
    public static PhaseResult startOrderPhase(Id opportunityId) {
        SC_OrderCrew.Result r = SC_OrderCrew.run(opportunityId);
        if (!r.success) return makeFail('Order', r.errorMessage);

        PhaseResult result = makeOk('Order', r.agentEmail);
        result.opportunityId = opportunityId;
        result.orderId       = r.orderId;
        result.orderNumber   = r.orderNumber;

        // Refresh orderId from Salesforce if needed
        if (String.isBlank(result.orderId)) {
            List<Order> orders = [
                SELECT Id, OrderNumber FROM Order
                WHERE OpportunityId = :opportunityId
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!orders.isEmpty()) {
                result.orderId     = orders[0].Id;
                result.orderNumber = orders[0].OrderNumber;
            }
        }
        return result;
    }

    // ─── Utility: Log Customer Reply ──────────────────────────────────────────

    /**
     * Logs an inbound customer message to the conversation history.
     * Call this before each handleReply/phase call to simulate the customer's email.
     *
     * @param leadId        Lead Id (use during Lead stage)
     * @param opportunityId Opportunity Id (use after conversion)
     * @param stage         Sales stage: Lead / Opportunity / Quote / Payment / Order
     * @param message       The customer's email body text
     */
    public static void logCustomerReply(Id leadId, Id opportunityId, String stage, String message) {
        if (String.isBlank(message)) return;

        SC_ConversationMessage__c msg = new SC_ConversationMessage__c(
            Direction__c  = 'Inbound',
            Stage__c      = stage,
            Subject__c    = 'Customer Reply — ' + stage,
            Body__c       = message,
            FromEmail__c  = 'customer@example.com',
            ToEmail__c    = 'sales-agent@forcecrew.ai',
            AgentName__c  = 'Customer',
            SentDate__c   = DateTime.now()
        );
        if (leadId != null)        msg.LeadId__c        = leadId;
        if (opportunityId != null) msg.OpportunityId__c = opportunityId;

        insert msg;
    }

    // ─── Utility: Get Conversation Log ───────────────────────────────────────

    /**
     * Returns the full conversation thread for display.
     */
    public static List<SC_ConversationMessage__c> getConversationLog(Id leadId, Id opportunityId) {
        String soql = 'SELECT Id, Name, Direction__c, Stage__c, Subject__c, Body__c, '
                    + 'AgentName__c, SentDate__c FROM SC_ConversationMessage__c WHERE ';

        List<String> conditions = new List<String>();
        if (leadId != null)        conditions.add('LeadId__c = \'' + leadId + '\'');
        if (opportunityId != null) conditions.add('OpportunityId__c = \'' + opportunityId + '\'');
        if (conditions.isEmpty())  return new List<SC_ConversationMessage__c>();

        soql += '(' + String.join(conditions, ' OR ') + ') ORDER BY SentDate__c ASC NULLS FIRST';
        return Database.query(soql);
    }

    // ─── Utility: Get PayPal Invoice ─────────────────────────────────────────

    /**
     * Returns the most recent PayPal invoice for an Opportunity.
     */
    public static SC_PayPalInvoice__c getLatestInvoice(Id opportunityId) {
        List<SC_PayPalInvoice__c> invoices = [
            SELECT Id, Name, Status__c, Amount__c, PaymentLink__c, DueDate__c, PaidDate__c
            FROM SC_PayPalInvoice__c
            WHERE OpportunityId__c = :opportunityId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return invoices.isEmpty() ? null : invoices[0];
    }
}
