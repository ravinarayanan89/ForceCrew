/**
 * SC_CreatePayPalInvoiceTool - Creates a SC_PayPalInvoice__c record simulating a PayPal invoice.
 *
 * In this demo, the PayPal integration is simulated — a SC_PayPalInvoice__c record is created
 * with a mock PayPal Invoice ID and a demo payment link. In production, replace the mock
 * data with an HTTP callout to the PayPal Invoicing API (POST /v2/invoicing/invoices).
 *
 * Returns the invoice Id and the payment link to share with the customer.
 *
 * @group SalesCycle
 */
public with sharing class SC_CreatePayPalInvoiceTool implements FC_IMCPTool {

    public String getName() {
        return 'CreatePayPalInvoice';
    }

    public String getDescription() {
        return 'Creates a PayPal invoice for the deal and returns a payment link to send to the customer. '
            + 'The invoice is linked to the Opportunity. '
            + 'In this demo the PayPal call is simulated — a real integration would call the PayPal API.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('opportunityId', FC_ToolParameter.TYPE_STRING)
                .description('The Opportunity Id for this invoice')
                .required()
                .build(),
            new FC_ToolParameter.Builder('contactId', FC_ToolParameter.TYPE_STRING)
                .description('The Contact Id of the customer receiving the invoice')
                .required()
                .build(),
            new FC_ToolParameter.Builder('amount', FC_ToolParameter.TYPE_NUMBER)
                .description('Invoice total amount. If not provided, uses the Opportunity Amount.')
                .build(),
            new FC_ToolParameter.Builder('description', FC_ToolParameter.TYPE_STRING)
                .description('Invoice description visible to the customer')
                .build(),
            new FC_ToolParameter.Builder('dueDays', FC_ToolParameter.TYPE_INTEGER)
                .description('Number of days until payment is due. Default: 14')
                .defaultValue(14)
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String  oppId       = (String) params.get('opportunityId');
            String  contactId   = (String) params.get('contactId');
            String  description = (String) params.get('description');
            Integer dueDays     = params.containsKey('dueDays')
                ? Integer.valueOf(String.valueOf(params.get('dueDays')))
                : 14;

            if (String.isBlank(oppId)) {
                return error('opportunityId is required');
            }
            if (String.isBlank(contactId)) {
                return error('contactId is required');
            }

            Opportunity opp = [SELECT Id, Name, Amount FROM Opportunity WHERE Id = :oppId LIMIT 1];

            Decimal invoiceAmount = opp.Amount ?? 0;
            if (params.containsKey('amount') && params.get('amount') != null) {
                invoiceAmount = Decimal.valueOf(String.valueOf(params.get('amount')));
            }

            // Generate a mock PayPal invoice ID (INV2-XXXX-XXXX-XXXX-XXXX format)
            String mockPayPalId = 'INV2-' + generateMockId();

            // Mock payment link — in production this comes from PayPal API response
            String paymentLink = 'https://www.paypal.com/invoice/payerView/details/' + mockPayPalId;

            SC_PayPalInvoice__c invoice = new SC_PayPalInvoice__c(
                OpportunityId__c  = oppId,
                ContactId__c      = (Id) contactId,
                Amount__c         = invoiceAmount,
                Status__c         = 'Draft',
                PayPalInvoiceId__c = mockPayPalId,
                PaymentLink__c    = paymentLink,
                DueDate__c        = Date.today().addDays(dueDays),
                Description__c    = String.isNotBlank(description)
                    ? description
                    : 'Payment for: ' + opp.Name
            );
            insert invoice;

            // Update invoice status to Sent
            invoice.Status__c  = 'Sent';
            invoice.SentDate__c = DateTime.now();
            update invoice;

            return JSON.serialize(new Map<String, Object>{
                'success'        => true,
                'invoiceId'      => invoice.Id,
                'payPalInvoiceId' => mockPayPalId,
                'paymentLink'    => paymentLink,
                'amount'         => invoiceAmount,
                'dueDate'        => String.valueOf(invoice.DueDate__c),
                'message'        => 'PayPal invoice created and sent. Amount: $' + invoiceAmount
                    + '. Payment link: ' + paymentLink
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String generateMockId() {
        // Generates a mock PayPal-style invoice segment using a timestamp + hash
        Long ts = DateTime.now().getTime();
        String raw = String.valueOf(ts);
        return raw.substring(0, 4) + '-' + raw.substring(4, 8) + '-'
             + raw.substring(8, 12) + '-' + raw.substring(raw.length() - 4);
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
