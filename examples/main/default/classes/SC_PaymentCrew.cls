/**
 * SC_PaymentCrew - Multi-agent crew for the Payment phase of the AI sales cycle.
 *
 * Creates a PayPal invoice for the deal and sends the payment link to the customer.
 * Once payment is confirmed (via SC_SalesCycleCrew.markPaymentReceived), the
 * SC_OrderCrew takes over to create the fulfillment order.
 *
 * Usage:
 *   SC_PaymentCrew.Result r = SC_PaymentCrew.run(opportunityId);
 *
 * @group SalesCycle
 */
public with sharing class SC_PaymentCrew {

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class Result {
        public Boolean success       { get; private set; }
        public String  invoiceId     { get; private set; }
        public String  paymentLink   { get; private set; }
        public String  agentEmail    { get; private set; }
        public String  errorMessage  { get; private set; }

        private Result() {}

        public Result ok(FC_CrewResult cr) {
            Result r = new Result();
            r.success = true;
            if (cr.taskResults.size() >= 1) {
                // Extract invoiceId and paymentLink from invoice creation task output
                r.invoiceId   = extractJsonField(cr.taskResults[0].output, 'invoiceId');
                r.paymentLink = extractJsonField(cr.taskResults[0].output, 'paymentLink');
            }
            if (cr.taskResults.size() >= 2) r.agentEmail = cr.taskResults[1].output;
            return r;
        }

        public Result error(String msg) {
            Result r = new Result();
            r.success      = false;
            r.errorMessage = msg;
            return r;
        }
    }

    // ─── Entry Point ──────────────────────────────────────────────────────────

    /**
     * Creates a PayPal invoice and sends the payment link email to the customer.
     *
     * @param opportunityId  The Closed Won Opportunity Id
     */
    public static Result run(Id opportunityId) {
        if (opportunityId == null) return new Result().error('opportunityId is required');

        // ── Tools ─────────────────────────────────────────────────────────────
        FC_Tool queryTool       = FC_Tool.fromMCP(new FC_SampleSOQLTool());
        FC_Tool paypalTool      = FC_Tool.fromMCP(new SC_CreatePayPalInvoiceTool());
        FC_Tool emailTool       = FC_Tool.fromMCP(new SC_LogEmailTool());
        FC_Tool dmlTool = FC_Tool.fromMCP(new SC_DMLTool());

        // ── Agents ────────────────────────────────────────────────────────────
        FC_Agent invoiceCreator = new FC_Agent.Builder('Invoice Creator')
            .goal('Query the Opportunity and Contact details, then create a PayPal invoice '
                + 'for the agreed amount using CreatePayPalInvoice.')
            .backstory('You are an accounts receivable specialist. You always query the opportunity '
                + 'to get the exact amount and the primary contact before creating an invoice. '
                + 'The invoice due date is 14 days from today. '
                + 'You also update the opportunity stage to "Negotiation/Review" after creating the invoice.')
            .tool(queryTool)
            .tool(paypalTool)
            .tool(dmlTool)
            .maxIterations(6)
            .build();

        FC_Agent paymentSender = new FC_Agent.Builder('Payment Link Sender')
            .goal('Send an email to the customer with the PayPal payment link from the invoice. '
                + 'Always call LogOutboundEmail to deliver the email.')
            .backstory('You are a professional account executive closing deals. '
                + 'Your payment request email is polite, clear, and creates urgency around the due date. '
                + 'You include the exact amount, the due date, and the clickable payment link. '
                + 'You remind them that paying promptly ensures their order is prioritised.')
            .tool(emailTool)
            .tool(queryTool)
            .maxIterations(4)
            .build();

        // ── Tasks ─────────────────────────────────────────────────────────────
        FC_Task invoiceTask = new FC_Task.Builder('Create PayPal Invoice')
            .description(
                'Create a PayPal invoice for the deal on Opportunity: ' + opportunityId + '.\n\n'
                + 'Steps:\n'
                + '1. Query the Opportunity:\n'
                + '   SELECT Id, Name, Amount, AccountId, Account.Name FROM Opportunity WHERE Id = \''
                + opportunityId + '\'.\n'
                + '2. Query the primary Contact linked to the Account:\n'
                + '   SELECT Id, FirstName, LastName, Email FROM Contact '
                + '   WHERE AccountId = <accountId from above> ORDER BY CreatedDate ASC LIMIT 1.\n'
                + '3. Call CreatePayPalInvoice with:\n'
                + '   opportunityId="' + opportunityId + '",\n'
                + '   contactId=<Contact Id>,\n'
                + '   amount=<Opportunity Amount>,\n'
                + '   description="Payment for " + Opportunity Name,\n'
                + '   dueDays=14.\n'
                + '4. Call DMLRecord with operation="update", objectApiName="Opportunity", '
                + '   recordId="' + opportunityId + '", fields={"StageName":"Negotiation/Review"}.'
            )
            .expectedOutput('Invoice Id, PayPal invoice ID, payment link URL, amount, and due date.')
            .assignToAgent('Invoice Creator')
            .build();

        FC_Task sendPaymentTask = new FC_Task.Builder('Send Payment Link Email')
            .description(
                'Send the payment link to the customer.\n\n'
                + '1. Use QueryRecords (opportunityId="' + opportunityId + '") '
                + '   to get the customer\'s email address.\n'
                + '2. Compose a professional payment request email that includes:\n'
                + '   - Congratulations on the deal agreement\n'
                + '   - The total amount due\n'
                + '   - The payment due date (14 days from today)\n'
                + '   - The PayPal payment link (from the Create PayPal Invoice task)\n'
                + '   - Instructions: "Click the link to pay securely via PayPal"\n'
                + '   - A note that their order will be created and processed upon payment\n'
                + '3. Call LogOutboundEmail with:\n'
                + '   stage="Payment", opportunityId="' + opportunityId + '",\n'
                + '   agentName="Payment Link Sender".'
            )
            .expectedOutput('Confirmation email sent. Full email text including payment link.')
            .assignToAgent('Payment Link Sender')
            .withContext('Create PayPal Invoice')
            .build();

        // ── Assemble and Run ──────────────────────────────────────────────────
        try {
            FC_CrewResult crewResult = new FC_Crew.Builder('Payment Crew')
                .agent(invoiceCreator)
                .agent(paymentSender)
                .task(invoiceTask)
                .task(sendPaymentTask)
                .verbose(true)
                .failFast(true)
                .build()
                .kickoff();

            if (crewResult.success) {
                return new Result().ok(crewResult);
            } else {
                return new Result().error(crewResult.errorMessage);
            }
        } catch (Exception e) {
            return new Result().error('SC_PaymentCrew failed: ' + e.getMessage());
        }
    }

    private static String extractJsonField(String payload, String field) {
        if (String.isBlank(payload)) return null;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(payload);
            Object val = parsed.get(field);
            return val != null ? String.valueOf(val) : null;
        } catch (Exception e) {
            return null;
        }
    }
}
