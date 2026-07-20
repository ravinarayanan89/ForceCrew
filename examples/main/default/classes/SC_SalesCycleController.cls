/**
 * SC_SalesCycleController - @AuraEnabled bridge for the AI Sales Cycle Demo LWC.
 *
 * Exposes all SC_SalesCycleCrew phase entry points to Lightning Web Components
 * and other Salesforce UI surfaces. Each method corresponds to one step in the
 * demo runner script.
 *
 * @group SalesCycle
 */
public with sharing class SC_SalesCycleController {

    // ─── Phase Triggers ───────────────────────────────────────────────────────

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult startLeadOutreach(Id leadId) {
        try {
            return SC_SalesCycleCrew.startLeadOutreach(leadId);
        } catch (Exception e) {
            throw new AuraHandledException('Lead Outreach failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult handleLeadReply(Id leadId, String customerMessage) {
        try {
            SC_SalesCycleCrew.logCustomerReply(leadId, null, 'Lead', customerMessage);
            return SC_SalesCycleCrew.handleLeadReply(leadId, customerMessage);
        } catch (Exception e) {
            throw new AuraHandledException('Handle Lead Reply failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult startOpportunityPhase(Id opportunityId, String customerMessage) {
        try {
            SC_SalesCycleCrew.logCustomerReply(null, opportunityId, 'Opportunity', customerMessage);
            return SC_SalesCycleCrew.startOpportunityPhase(opportunityId, customerMessage);
        } catch (Exception e) {
            throw new AuraHandledException('Opportunity Phase failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult startQuotePhase(Id opportunityId) {
        try {
            return SC_SalesCycleCrew.startQuotePhase(opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Quote Phase failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult negotiateQuote(Id opportunityId, String customerMessage) {
        try {
            SC_SalesCycleCrew.logCustomerReply(null, opportunityId, 'Quote', customerMessage);
            return SC_SalesCycleCrew.negotiateQuote(opportunityId, customerMessage);
        } catch (Exception e) {
            throw new AuraHandledException('Quote Negotiation failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult startPaymentPhase(Id opportunityId) {
        try {
            return SC_SalesCycleCrew.startPaymentPhase(opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Payment Phase failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult markPaymentReceived(Id invoiceId) {
        try {
            return SC_SalesCycleCrew.markPaymentReceived(invoiceId);
        } catch (Exception e) {
            throw new AuraHandledException('Mark Payment Received failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SC_SalesCycleCrew.PhaseResult startOrderPhase(Id opportunityId) {
        try {
            return SC_SalesCycleCrew.startOrderPhase(opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Order Phase failed: ' + e.getMessage());
        }
    }

    // ─── Conversation Log ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<SC_ConversationMessage__c> getConversationLog(Id leadId, Id opportunityId) {
        try {
            return SC_SalesCycleCrew.getConversationLog(leadId, opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load conversation: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static SC_PayPalInvoice__c getLatestInvoice(Id opportunityId) {
        try {
            return SC_SalesCycleCrew.getLatestInvoice(opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load invoice: ' + e.getMessage());
        }
    }

    // ─── Helpers for Demo Setup ───────────────────────────────────────────────

    /**
     * Returns a list of unconverted Leads for the demo picker.
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead> getUnconvertedLeads() {
        return [
            SELECT Id, FirstName, LastName, Company, Email, Status, LeadSource
            FROM Lead
            WHERE IsConverted = false
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    /**
     * Returns open Opportunities for the demo picker.
     */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpenOpportunities() {
        return [
            SELECT Id, Name, StageName, Amount, Account.Name, CloseDate
            FROM Opportunity
            WHERE IsClosed = false
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }
}
