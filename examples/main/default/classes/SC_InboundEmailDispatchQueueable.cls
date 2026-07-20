/**
 * SC_InboundEmailDispatchQueueable - Async crew dispatcher for inbound customer emails.
 *
 * The Messaging.InboundEmailHandler runs synchronously and has a tight governor limit budget.
 * LLM calls (FC_ModelsAPIService / aiplatform.ModelsAPI) are long-running and consume
 * significant CPU/heap. Running them in a Queueable avoids hitting limits in the
 * email handler context.
 *
 * Routing logic (matches SC_SalesCycleCrew phase structure):
 *
 *   Stage = Lead                → SC_SalesCycleCrew.handleLeadReply()
 *   Stage = Opportunity         → SC_SalesCycleCrew.startOpportunityPhase()
 *   Stage = Quote               → SC_SalesCycleCrew.negotiateQuote()
 *   Stage = Payment             → (no agent action — waiting for PayPal webhook)
 *   Stage = Order               → (no agent action — order is already complete)
 *
 * @group SalesCycle
 */
public with sharing class SC_InboundEmailDispatchQueueable implements Queueable {

    private SC_InboundEmailHandler.EmailContext ctx;
    private String customerMessage;

    public SC_InboundEmailDispatchQueueable(
        SC_InboundEmailHandler.EmailContext ctx,
        String customerMessage
    ) {
        this.ctx             = ctx;
        this.customerMessage = customerMessage;
    }

    public void execute(QueueableContext context) {
        try {
            FC_Logger.info('SC_InboundEmailDispatch',
                'Dispatching for stage=' + ctx.stage
                + ' | leadId=' + ctx.leadId
                + ' | oppId=' + ctx.opportunityId);

            String stage = ctx.stage ?? 'Lead';

            if (stage == 'Lead') {
                // Agent reads conversation, responds or converts the lead
                if (ctx.leadId == null) {
                    FC_Logger.warn('SC_InboundEmailDispatch', 'Lead stage but no leadId — skipping');
                    return;
                }
                SC_SalesCycleCrew.PhaseResult r =
                    SC_SalesCycleCrew.handleLeadReply(ctx.leadId, customerMessage);

                FC_Logger.info('SC_InboundEmailDispatch',
                    'Lead reply handled. success=' + r.success
                    + (r.opportunityId != null ? ' | converted oppId=' + r.opportunityId : '')
                    + (String.isNotBlank(r.errorMessage) ? ' | error=' + r.errorMessage : ''));

            } else if (stage == 'Opportunity') {
                // Agent matches products to customer's stated needs
                if (ctx.opportunityId == null) {
                    FC_Logger.warn('SC_InboundEmailDispatch', 'Opportunity stage but no opportunityId — skipping');
                    return;
                }
                SC_SalesCycleCrew.PhaseResult r =
                    SC_SalesCycleCrew.startOpportunityPhase(ctx.opportunityId, customerMessage);

                FC_Logger.info('SC_InboundEmailDispatch',
                    'Opportunity phase handled. success=' + r.success
                    + (String.isNotBlank(r.errorMessage) ? ' | error=' + r.errorMessage : ''));

            } else if (stage == 'Quote') {
                // Agent handles negotiation or quote acceptance
                if (ctx.opportunityId == null) {
                    FC_Logger.warn('SC_InboundEmailDispatch', 'Quote stage but no opportunityId — skipping');
                    return;
                }

                // Determine: is customer accepting or negotiating?
                String lc = customerMessage.toLowerCase();
                Boolean isAcceptance = lc.contains('accepted') || lc.contains('approved')
                    || lc.contains('proceed') || lc.contains('go ahead') || lc.contains('looks good')
                    || lc.contains('send invoice') || lc.contains('send payment');

                if (isAcceptance) {
                    // Customer accepted — move to payment
                    FC_Logger.info('SC_InboundEmailDispatch', 'Customer accepted quote — starting payment phase');
                    SC_SalesCycleCrew.PhaseResult r =
                        SC_SalesCycleCrew.startPaymentPhase(ctx.opportunityId);

                    FC_Logger.info('SC_InboundEmailDispatch',
                        'Payment phase started. success=' + r.success
                        + (String.isNotBlank(r.paymentLink) ? ' | link=' + r.paymentLink : '')
                        + (String.isNotBlank(r.errorMessage) ? ' | error=' + r.errorMessage : ''));
                } else {
                    // Customer is negotiating
                    SC_SalesCycleCrew.PhaseResult r =
                        SC_SalesCycleCrew.negotiateQuote(ctx.opportunityId, customerMessage);

                    FC_Logger.info('SC_InboundEmailDispatch',
                        'Negotiation handled. success=' + r.success
                        + (String.isNotBlank(r.errorMessage) ? ' | error=' + r.errorMessage : ''));
                }

            } else if (stage == 'Payment') {
                // Payment stage — agent can answer questions but doesn't take automated action
                // Real payment confirmation comes from a PayPal webhook, not the customer email
                FC_Logger.info('SC_InboundEmailDispatch',
                    'Inbound email during Payment stage — no automated action. '
                    + 'Awaiting PayPal payment confirmation webhook.');

            } else if (stage == 'Order') {
                // Order is complete — reply is a post-sale question, no crew action needed
                FC_Logger.info('SC_InboundEmailDispatch',
                    'Inbound email during Order stage — sales cycle complete. '
                    + 'Route to customer success.');
            }

        } catch (Exception e) {
            FC_Logger.error('SC_InboundEmailDispatch',
                'Dispatch failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}
