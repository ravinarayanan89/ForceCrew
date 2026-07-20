/**
 * SC_OpportunityCrew - Multi-agent crew for the Opportunity phase of the AI sales cycle.
 *
 * Reads the customer's stated needs from the conversation, searches the product catalog,
 * adds matching products to the Opportunity, and sends a follow-up email summarising
 * what was configured.
 *
 * Usage:
 *   SC_OpportunityCrew.Result r = SC_OpportunityCrew.run(opportunityId, customerMessage);
 *
 * @group SalesCycle
 */
public with sharing class SC_OpportunityCrew {

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class Result {
        public Boolean success         { get; private set; }
        public String  productSummary  { get; private set; }
        public String  agentEmail      { get; private set; }
        public String  errorMessage    { get; private set; }

        private Result() {}

        public Result ok(FC_CrewResult cr) {
            Result r = new Result();
            r.success = true;
            if (cr.taskResults.size() >= 2) r.productSummary = cr.taskResults[1].output;
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

    // ─── Entry Point ──────────────────────────────────────────────────────────

    /**
     * Discovers products from conversation context and adds them to the Opportunity.
     *
     * @param opportunityId  Salesforce Opportunity Id (just converted from lead)
     * @param customerMessage  The customer's message describing their needs
     */
    public static Result run(Id opportunityId, String customerMessage) {
        if (opportunityId == null)           return new Result().error('opportunityId is required');
        if (String.isBlank(customerMessage)) return new Result().error('customerMessage is required');

        // ── Tools ─────────────────────────────────────────────────────────────
        FC_Tool queryTool      = FC_Tool.fromMCP(new FC_SampleSOQLTool());
        FC_Tool addProductTool = FC_Tool.fromMCP(new SC_AddProductTool());
        FC_Tool dmlTool        = FC_Tool.fromMCP(new SC_DMLTool());
        FC_Tool emailTool      = FC_Tool.fromMCP(new SC_LogEmailTool());

        // ── Agents ────────────────────────────────────────────────────────────
        FC_Agent needsAnalyst = new FC_Agent.Builder('Needs Analyst')
            .goal('Understand what the customer wants based on their message and the conversation history. '
                + 'Identify 1-3 specific product categories or capability keywords to search for.')
            .backstory('You are a solutions consultant who listens carefully to customer needs. '
                + 'You extract concrete product requirements from customer language. '
                + 'Use QueryRecords to read the full thread before analysing.')
            .tool(queryTool)
            .maxIterations(4)
            .build();

        FC_Agent productSpecialist = new FC_Agent.Builder('Product Specialist')
            .goal('Use QueryRecords to search the pricebook, find the 1-3 best matching products, '
                + 'and add each one to the Opportunity using AddProductToOpportunity.')
            .backstory('You are a product expert who matches customer needs to catalog items. '
                + 'Always query the standard pricebook first, then add products. '
                + 'If no products match, add the closest available option and note the mismatch. '
                + 'You always add at least one product.')
            .tool(queryTool)
            .tool(addProductTool)
            .tool(dmlTool)
            .maxIterations(8)
            .build();

        FC_Agent followUpAgent = new FC_Agent.Builder('Opportunity Follow-up Agent')
            .goal('Send a follow-up email to the customer summarising the products configured '
                + 'on their opportunity and confirming next steps.')
            .backstory('You are a consultative sales rep who always confirms what was discussed. '
                + 'Your follow-up emails are warm, specific, and end with a clear next step (quote review). '
                + 'Always call LogOutboundEmail to send — never just return the email text.')
            .tool(emailTool)
            .maxIterations(4)
            .build();

        // ── Tasks ─────────────────────────────────────────────────────────────
        FC_Task needsTask = new FC_Task.Builder('Analyse Customer Needs')
            .description(
                'The customer has shared their requirements. Their message:\n\n'
                + '"' + customerMessage + '"\n\n'
                + 'Run these QueryRecords calls:\n'
                + '1. SELECT Direction__c, Stage__c, Body__c, SentDate__c FROM SC_ConversationMessage__c '
                + '   WHERE OpportunityId__c = \'' + opportunityId + '\' ORDER BY SentDate__c ASC LIMIT 20\n'
                + '2. SELECT Id, Name, AccountId, Account.Name, StageName FROM Opportunity WHERE Id = \''
                + opportunityId + '\'\n\n'
                + 'Extract: what problem they want to solve, what features they mentioned, '
                + 'any budget or scale hints.'
            )
            .expectedOutput('A structured needs summary: problem statement, desired capabilities (as keywords), '
                + 'budget range if mentioned, company context.')
            .assignToAgent('Needs Analyst')
            .build();

        FC_Task productTask = new FC_Task.Builder('Configure Products')
            .description(
                'Based on the customer needs analysis, do the following:\n\n'
                + '1. Query pricebook entries: SELECT Id, UnitPrice, Product2.Name, Product2.Description '
                + '   FROM PricebookEntry WHERE IsActive = true AND Pricebook2.IsStandard = true LIMIT 20\n'
                + '2. Select the 1-3 most relevant products from the results.\n'
                + '3. Add each selected product using AddProductToOpportunity '
                + '   (opportunityId="' + opportunityId + '"). Use quantity=1 for each.\n'
                + '4. Call DMLRecord with operation="update", objectApiName="Opportunity", '
                + '   recordId="' + opportunityId + '", fields={"StageName":"Needs Analysis"}.'
            )
            .expectedOutput('List of products added: name, unitPrice, quantity for each. '
                + 'Opportunity stage updated to Needs Analysis.')
            .assignToAgent('Product Specialist')
            .withContext('Analyse Customer Needs')
            .build();

        FC_Task followUpTask = new FC_Task.Builder('Send Product Follow-up Email')
            .description(
                'Send a follow-up email to the customer:\n\n'
                + '1. Summarise the products you\'ve configured for them (from prior task output)\n'
                + '2. Explain why these products address their stated needs\n'
                + '3. Tell them you\'ll prepare a formal quote for review\n'
                + '4. Call LogOutboundEmail with:\n'
                + '   stage="Opportunity", opportunityId="' + opportunityId + '",\n'
                + '   agentName="Opportunity Follow-up Agent",\n'
                + '   toEmail=<customer email from conversation history>'
            )
            .expectedOutput('Confirmation that LogOutboundEmail was called. Include the email text.')
            .assignToAgent('Opportunity Follow-up Agent')
            .withContext('Analyse Customer Needs')
            .withContext('Configure Products')
            .build();

        // ── Assemble and Run ──────────────────────────────────────────────────
        try {
            FC_CrewResult crewResult = new FC_Crew.Builder('Opportunity Crew')
                .agent(needsAnalyst)
                .agent(productSpecialist)
                .agent(followUpAgent)
                .task(needsTask)
                .task(productTask)
                .task(followUpTask)
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
            return new Result().error('SC_OpportunityCrew failed: ' + e.getMessage());
        }
    }
}
