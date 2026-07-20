/**
 * SC_QuoteCrew - Multi-agent crew for the Quote phase of the AI sales cycle.
 *
 * Two modes:
 *
 *   createAndSend(opportunityId)
 *     Creates a formal Quote from the Opportunity, then emails it to the customer.
 *     Agents: Quote Builder · Pricing Reviewer · Quote Sender
 *
 *   negotiate(opportunityId, customerMessage)
 *     Reads the customer's negotiation request, decides on a discount,
 *     applies it, and sends an updated quote email.
 *     Agents: Negotiation Reader · Pricing Negotiator · Updated Quote Sender
 *
 * Usage:
 *   SC_QuoteCrew.Result r = SC_QuoteCrew.createAndSend(opportunityId);
 *   SC_QuoteCrew.Result r = SC_QuoteCrew.negotiate(opportunityId, 'Can you do 10% off?');
 *
 * @group SalesCycle
 */
public with sharing class SC_QuoteCrew {

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class Result {
        public Boolean success       { get; private set; }
        public String  quoteId       { get; private set; }
        public String  pricingSummary { get; private set; }
        public String  agentEmail    { get; private set; }
        public String  errorMessage  { get; private set; }

        private Result() {}

        public Result ok(FC_CrewResult cr, String quoteIdVal) {
            Result r   = new Result();
            r.success  = true;
            r.quoteId  = quoteIdVal;
            if (cr.taskResults.size() >= 2) r.pricingSummary = cr.taskResults[1].output;
            if (cr.taskResults.size() >= 3) r.agentEmail     = cr.taskResults[2].output;
            return r;
        }

        public Result error(String msg) {
            Result r = new Result();
            r.success      = false;
            r.errorMessage = msg;
            return r;
        }
    }

    // ─── Shared Tools ─────────────────────────────────────────────────────────

    private static FC_Tool queryTool()    { return FC_Tool.fromMCP(new FC_SampleSOQLTool()); }
    private static FC_Tool convTool()     { return queryTool(); }
    private static FC_Tool quoteTool()    { return FC_Tool.fromMCP(new SC_CreateQuoteTool()); }
    private static FC_Tool discountTool() { return FC_Tool.fromMCP(new SC_ApplyDiscountTool()); }
    private static FC_Tool emailTool()    { return FC_Tool.fromMCP(new SC_LogEmailTool()); }
    private static FC_Tool updateOppTool(){ return FC_Tool.fromMCP(new SC_DMLTool()); }

    // ─── Mode 1: Create and Send Quote ────────────────────────────────────────

    /**
     * Creates a Quote from the Opportunity products and emails it to the customer.
     */
    public static Result createAndSend(Id opportunityId) {
        if (opportunityId == null) return new Result().error('opportunityId is required');

        FC_Agent quoteBuilder = new FC_Agent.Builder('Quote Builder')
            .goal('Create a Salesforce Quote for this Opportunity using CreateQuote. '
                + 'First query the Opportunity to confirm it has products. '
                + 'Then create the quote.')
            .backstory('You are a meticulous deal desk analyst. You always query the opportunity '
                + 'details before creating a quote. You set a 30-day expiration.')
            .tool(queryTool())
            .tool(quoteTool())
            .tool(updateOppTool())
            .maxIterations(6)
            .build();

        FC_Agent pricingReviewer = new FC_Agent.Builder('Pricing Reviewer')
            .goal('Review the quote details and recommend whether standard pricing is appropriate '
                + 'or if any standard promotional discount should be applied.')
            .backstory('You are a pricing strategist. You check company size and deal size '
                + 'to determine if a 5-10% loyalty/volume discount makes commercial sense. '
                + 'For deals under $10k, recommend no discount. For $10k-$50k, 5% is reasonable. '
                + 'Above $50k, 10% can be offered proactively to accelerate close.')
            .build();

        FC_Agent quoteSender = new FC_Agent.Builder('Quote Sender')
            .goal('Send a professional quote email to the customer. '
                + 'Always call LogOutboundEmail to deliver the email.')
            .backstory('You are a professional AE sending formal quotes. '
                + 'Your email introduces the quote, highlights value, states the expiry date, '
                + 'and invites the customer to discuss. You always call LogOutboundEmail.')
            .tool(emailTool())
            .tool(discountTool())
            .tool(convTool())
            .maxIterations(5)
            .build();

        FC_Task buildTask = new FC_Task.Builder('Build Quote')
            .description(
                'Create a formal quote for Opportunity Id: ' + opportunityId + '.\n\n'
                + 'Steps:\n'
                + '1. Query the Opportunity: SELECT Id, Name, Amount, AccountId, Account.Name, '
                + '   Pricebook2Id, CloseDate, StageName FROM Opportunity WHERE Id = \'' + opportunityId + '\'.\n'
                + '2. Call CreateQuote with opportunityId="' + opportunityId + '", '
                + '   expirationDays=30.\n'
                + '3. Call DMLRecord with operation="update", objectApiName="Opportunity", '
                + '   recordId="' + opportunityId + '", fields={"StageName":"Proposal/Price Quote"}.'
            )
            .expectedOutput('Quote Id, quote name, expiration date, line items list with totals.')
            .assignToAgent('Quote Builder')
            .build();

        FC_Task pricingTask = new FC_Task.Builder('Review Pricing')
            .description(
                'Review the quote and decide if a proactive discount is appropriate.\n\n'
                + 'Quote details are in the prior task output. '
                + 'Check the total amount and account profile to make your recommendation.'
            )
            .expectedOutput('Pricing recommendation: apply N% discount (or no discount) with brief justification.')
            .assignToAgent('Pricing Reviewer')
            .withContext('Build Quote')
            .build();

        FC_Task sendTask = new FC_Task.Builder('Send Quote Email')
            .description(
                'Send the formal quote to the customer.\n\n'
                + '1. Get the customer\'s email from conversation history: '
                + 'QueryRecords(opportunityId="' + opportunityId + '").\n'
                + '2. If the Pricing Reviewer recommended a discount, apply it first: '
                + '   ApplyQuoteDiscount(quoteId=<from Build Quote task>, discountPercent=<recommended>).\n'
                + '3. Compose a professional quote email that:\n'
                + '   - Mentions the products included\n'
                + '   - States the total (after any discount)\n'
                + '   - Highlights the expiration date\n'
                + '   - Ends with a CTA to reply with questions or approval\n'
                + '4. Call LogOutboundEmail with stage="Quote", opportunityId="' + opportunityId + '".'
            )
            .expectedOutput('Confirmation that email was sent and full email text. Quote Id confirmed.')
            .assignToAgent('Quote Sender')
            .withContext('Build Quote')
            .withContext('Review Pricing')
            .build();

        return runCrew('Quote Crew', quoteBuilder, pricingReviewer, quoteSender,
                       buildTask, pricingTask, sendTask, opportunityId);
    }

    // ─── Mode 2: Negotiate ────────────────────────────────────────────────────

    /**
     * Handles a customer discount request and sends an updated quote.
     */
    public static Result negotiate(Id opportunityId, String customerMessage) {
        if (opportunityId == null)           return new Result().error('opportunityId is required');
        if (String.isBlank(customerMessage)) return new Result().error('customerMessage is required');

        FC_Agent convReader = new FC_Agent.Builder('Negotiation Reader')
            .goal('Read the conversation history and the current quote to understand '
                + 'what the customer is asking for in terms of pricing changes.')
            .backstory('You are a commercial analyst. You read conversations to extract '
                + 'the exact discount % requested and any deal urgency signals. '
                + 'Use QueryRecords to read the full thread. '
                + 'Use QueryRecords to find the most recent Quote for this opportunity.')
            .tool(convTool())
            .tool(queryTool())
            .maxIterations(5)
            .build();

        FC_Agent negotiator = new FC_Agent.Builder('Pricing Negotiator')
            .goal('Decide what counter-offer to make. Approve the request if it is within '
                + 'policy (up to 15% discount). Offer a smaller discount if the ask is too high. '
                + 'Never approve more than 20% without strong justification.')
            .backstory('You are a VP of Sales with authority to approve discounts up to 15%. '
                + 'You are firm but fair. If the customer asks for 10% and you can approve it, do so. '
                + 'If they ask for 25%, counter with 15%. Always state your final approved discount %.')
            .build();

        FC_Agent counterAgent = new FC_Agent.Builder('Counter-Offer Agent')
            .goal('Apply the approved discount to the quote and send an updated quote email. '
                + 'Call ApplyQuoteDiscount then LogOutboundEmail.')
            .backstory('You are a deal desk analyst who applies approved discounts and communicates '
                + 'changes to the customer. You always confirm the new total in the email. '
                + 'Make the email warm — treat this as a win for the customer.')
            .tool(discountTool())
            .tool(emailTool())
            .maxIterations(5)
            .build();

        FC_Task readTask = new FC_Task.Builder('Read Negotiation Context')
            .description(
                'The customer wants to negotiate pricing. Their message:\n"' + customerMessage + '"\n\n'
                + 'Use QueryRecords (opportunityId="' + opportunityId + '") to read the thread.\n'
                + 'Use QueryRecords to get the current Quote: '
                + 'SELECT Id, Name, TotalPrice, ExpirationDate FROM Quote '
                + 'WHERE OpportunityId = \'' + opportunityId + '\' ORDER BY CreatedDate DESC LIMIT 1.'
            )
            .expectedOutput('Current quote details (Id, total, expiry) + customer\'s negotiation ask.')
            .assignToAgent('Negotiation Reader')
            .build();

        FC_Task negotiateTask = new FC_Task.Builder('Decide Counter-Offer')
            .description(
                'Customer asks: "' + customerMessage + '"\n\n'
                + 'Based on our policy (max 15% without escalation):\n'
                + '- If they ask for ≤15%: approve as requested\n'
                + '- If they ask for >15%: counter with 15%\n'
                + '- If the ask is unclear: assume they want 10%\n\n'
                + 'State clearly: APPROVED DISCOUNT: N%'
            )
            .expectedOutput('APPROVED DISCOUNT: N% with a 2-sentence explanation of the decision.')
            .assignToAgent('Pricing Negotiator')
            .withContext('Read Negotiation Context')
            .build();

        FC_Task counterTask = new FC_Task.Builder('Apply Discount and Respond')
            .description(
                'Apply the approved discount and send an updated quote email.\n\n'
                + '1. Call ApplyQuoteDiscount with:\n'
                + '   quoteId=<from Read Negotiation Context task>,\n'
                + '   discountPercent=<APPROVED DISCOUNT from prior task>,\n'
                + '   reason="Customer negotiation — approved discount"\n'
                + '2. Compose an email that:\n'
                + '   - Acknowledges their request positively\n'
                + '   - States the new discounted total clearly\n'
                + '   - Confirms the quote expiration date\n'
                + '   - Asks for their approval to proceed\n'
                + '3. Call LogOutboundEmail with stage="Quote", opportunityId="' + opportunityId + '".'
            )
            .expectedOutput('Confirmation that discount applied and email sent. New total amount stated.')
            .assignToAgent('Counter-Offer Agent')
            .withContext('Read Negotiation Context')
            .withContext('Decide Counter-Offer')
            .build();

        return runCrew('Quote Negotiation Crew', convReader, negotiator, counterAgent,
                       readTask, negotiateTask, counterTask, opportunityId);
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    private static Result runCrew(String crewName,
                                  FC_Agent a1, FC_Agent a2, FC_Agent a3,
                                  FC_Task t1, FC_Task t2, FC_Task t3,
                                  Id opportunityId) {
        try {
            FC_CrewResult crewResult = new FC_Crew.Builder(crewName)
                .agent(a1).agent(a2).agent(a3)
                .task(t1).task(t2).task(t3)
                .verbose(true)
                .failFast(true)
                .build()
                .kickoff();

            if (crewResult.success) {
                // Extract quoteId from first task output if present
                String quoteId = extractJsonField(crewResult.taskResults[0].output, 'quoteId');
                return new Result().ok(crewResult, quoteId);
            } else {
                return new Result().error(crewResult.errorMessage);
            }
        } catch (Exception e) {
            return new Result().error('SC_QuoteCrew failed: ' + e.getMessage());
        }
    }

    private static String extractJsonField(String payload, String field) {
        if (String.isBlank(payload)) return null;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(payload);
            return String.valueOf(parsed.get(field));
        } catch (Exception e) {
            return null;
        }
    }
}
