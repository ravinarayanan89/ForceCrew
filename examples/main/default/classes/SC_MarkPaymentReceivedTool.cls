/**
 * SC_MarkPaymentReceivedTool - Marks a PayPal invoice as paid and closes the Opportunity as Won.
 *
 * Called by the Payment Agent after the customer completes payment.
 * In production this would be triggered by a PayPal webhook (IPN/webhook event: INVOICE.PAID).
 * Here it is called manually to advance the demo.
 *
 * @group SalesCycle
 */
public with sharing class SC_MarkPaymentReceivedTool implements FC_IMCPTool {

    public String getName() {
        return 'MarkPaymentReceived';
    }

    public String getDescription() {
        return 'Marks a PayPal invoice as Paid and closes the linked Opportunity as Closed Won. '
            + 'Call this when the customer has completed payment. '
            + 'Returns the updated invoice and opportunity details.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('invoiceId', FC_ToolParameter.TYPE_STRING)
                .description('The SC_PayPalInvoice__c record Id')
                .required()
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String invoiceId = (String) params.get('invoiceId');
            if (String.isBlank(invoiceId)) {
                return error('invoiceId is required');
            }

            List<SC_PayPalInvoice__c> invoices = [
                SELECT Id, Status__c, Amount__c, OpportunityId__c, PayPalInvoiceId__c
                FROM SC_PayPalInvoice__c
                WHERE Id = :invoiceId LIMIT 1
            ];
            if (invoices.isEmpty()) {
                return error('Invoice not found: ' + invoiceId);
            }

            SC_PayPalInvoice__c inv = invoices[0];
            if (inv.Status__c == 'Paid') {
                return JSON.serialize(new Map<String, Object>{
                    'success'  => true,
                    'message'  => 'Invoice already marked as Paid.',
                    'invoiceId' => invoiceId
                });
            }

            inv.Status__c   = 'Paid';
            inv.PaidDate__c = DateTime.now();
            update inv;

            // Close the Opportunity as Won
            Opportunity opp = [SELECT Id, Name, Amount FROM Opportunity WHERE Id = :inv.OpportunityId__c LIMIT 1];
            opp.StageName = 'Closed Won';
            opp.CloseDate = Date.today();
            update opp;

            return JSON.serialize(new Map<String, Object>{
                'success'       => true,
                'invoiceId'     => inv.Id,
                'payPalId'      => inv.PayPalInvoiceId__c,
                'paidAmount'    => inv.Amount__c,
                'paidDate'      => String.valueOf(inv.PaidDate__c),
                'opportunityId' => opp.Id,
                'opportunityStage' => 'Closed Won',
                'message'       => 'Payment received! Invoice marked Paid. Opportunity "'
                    + opp.Name + '" closed as Won.'
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
