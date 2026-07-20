/**
 * SC_OrderCrew - Multi-agent crew for the Order phase of the AI sales cycle.
 *
 * Creates a Salesforce Order from the Closed Won Opportunity, activates it,
 * and sends a confirmation email to the customer with order details and next steps.
 *
 * Usage:
 *   SC_OrderCrew.Result r = SC_OrderCrew.run(opportunityId);
 *
 * @group SalesCycle
 */
public with sharing class SC_OrderCrew {

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class Result {
        public Boolean success       { get; private set; }
        public String  orderId       { get; private set; }
        public String  orderNumber   { get; private set; }
        public String  agentEmail    { get; private set; }
        public String  errorMessage  { get; private set; }

        private Result() {}

        public Result ok(FC_CrewResult cr) {
            Result r = new Result();
            r.success = true;
            if (cr.taskResults.size() >= 1) {
                r.orderId     = extractJsonField(cr.taskResults[0].output, 'orderId');
                r.orderNumber = extractJsonField(cr.taskResults[0].output, 'orderNumber');
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
     * Creates a Salesforce Order from a Closed Won Opportunity and sends a confirmation email.
     *
     * @param opportunityId  The Closed Won Opportunity Id
     */
    public static Result run(Id opportunityId) {
        if (opportunityId == null) return new Result().error('opportunityId is required');

        // ── Tools ─────────────────────────────────────────────────────────────
        FC_Tool queryTool    = FC_Tool.fromMCP(new FC_SampleSOQLTool());
        FC_Tool orderTool    = FC_Tool.fromMCP(new SC_CreateOrderTool());
        FC_Tool emailTool    = FC_Tool.fromMCP(new SC_LogEmailTool());
        FC_Tool dmlTool = FC_Tool.fromMCP(new SC_DMLTool());

        // ── Agents ────────────────────────────────────────────────────────────
        FC_Agent orderCreator = new FC_Agent.Builder('Order Creator')
            .goal('Create a Salesforce Order from the Closed Won Opportunity '
                + 'by calling CreateOrder, then confirm it is activated.')
            .backstory('You are a fulfillment operations manager. You create orders accurately. '
                + 'You always query the opportunity first to verify it is Closed Won. '
                + 'You set today as the effective date and pass the opportunityId. '
                + 'After creating the order, you also close out the opportunity stage.')
            .tool(queryTool)
            .tool(orderTool)
            .tool(dmlTool)
            .maxIterations(6)
            .build();

        FC_Agent confirmationAgent = new FC_Agent.Builder('Order Confirmation Agent')
            .goal('Send a warm, detailed order confirmation email to the customer. '
                + 'The email must include the order number, products ordered, and expected next steps. '
                + 'Always call LogOutboundEmail to deliver the email.')
            .backstory('You are a customer success manager who makes customers feel great about '
                + 'their purchase. Your confirmation email is enthusiastic, clear, and includes: '
                + 'order number, product list, a personal note of thanks, and an onboarding next step. '
                + 'Read the conversation history to personalise the message.')
            .tool(emailTool)
            .tool(queryTool)
            .maxIterations(4)
            .build();

        // ── Tasks ─────────────────────────────────────────────────────────────
        FC_Task orderTask = new FC_Task.Builder('Create Order')
            .description(
                'Create a Salesforce Order for the completed deal on Opportunity: ' + opportunityId + '.\n\n'
                + 'Steps:\n'
                + '1. Query the Opportunity:\n'
                + '   SELECT Id, Name, Amount, StageName, AccountId, Account.Name FROM Opportunity '
                + '   WHERE Id = \'' + opportunityId + '\'.\n'
                + '2. Call CreateOrder with:\n'
                + '   opportunityId="' + opportunityId + '",\n'
                + '   effectiveDate=today (YYYY-MM-DD),\n'
                + '   description="Order for: " + Opportunity Name.\n'
                + '3. Confirm the order is Activated (Status = Activated).\n'
                + '4. Call DMLRecord with operation="update", objectApiName="Opportunity", '
                + '   recordId="' + opportunityId + '", fields={"StageName":"Closed Won"}.'
            )
            .expectedOutput('Order Id, order number, activated status, list of order items.')
            .assignToAgent('Order Creator')
            .build();

        FC_Task confirmTask = new FC_Task.Builder('Send Order Confirmation Email')
            .description(
                'Send a detailed order confirmation email to the customer.\n\n'
                + '1. Use QueryRecords (opportunityId="' + opportunityId + '") '
                + '   to get the customer email and personalise the message.\n'
                + '2. Write an enthusiastic confirmation email that includes:\n'
                + '   - "Thank you for your order!" opening\n'
                + '   - Order number (from Create Order task)\n'
                + '   - Summary of products ordered\n'
                + '   - What happens next (implementation/onboarding kick-off)\n'
                + '   - An invitation to reply with any questions\n'
                + '   - Your name as the dedicated account contact\n'
                + '3. Call LogOutboundEmail with:\n'
                + '   stage="Order", opportunityId="' + opportunityId + '",\n'
                + '   agentName="Order Confirmation Agent",\n'
                + '   subject="Your Order is Confirmed — [Order Number]".'
            )
            .expectedOutput('Confirmation that LogOutboundEmail was called. Full email text.')
            .assignToAgent('Order Confirmation Agent')
            .withContext('Create Order')
            .build();

        // ── Assemble and Run ──────────────────────────────────────────────────
        try {
            FC_CrewResult crewResult = new FC_Crew.Builder('Order Crew')
                .agent(orderCreator)
                .agent(confirmationAgent)
                .task(orderTask)
                .task(confirmTask)
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
            return new Result().error('SC_OrderCrew failed: ' + e.getMessage());
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
