/**
 * SC_LeadCrew - Multi-agent crew for the Lead phase of the AI sales cycle.
 *
 * Two modes:
 *
 *   outreach(leadId)
 *     Research the lead → qualify → draft and send a personalised first-touch email.
 *     Agents: Lead Researcher · Lead Qualifier · Outreach Specialist
 *
 *   handleReply(leadId, customerMessage)
 *     Read the conversation thread → decide on response → reply and/or convert the lead.
 *     Agents: Conversation Reader · Sales Strategist · Action Executor
 *
 * Usage:
 *   SC_LeadCrew.Result r = SC_LeadCrew.outreach(leadId);
 *   SC_LeadCrew.Result r = SC_LeadCrew.handleReply(leadId, 'Hi, I am interested...');
 *
 * @group SalesCycle
 */
public with sharing class SC_LeadCrew {

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class Result {
        public Boolean success         { get; private set; }
        public String  agentEmail      { get; private set; }
        public String  qualificationReport { get; private set; }
        public String  conversionSummary  { get; private set; }
        public String  errorMessage    { get; private set; }

        private Result() {}

        public Result ok(FC_CrewResult cr, String mode) {
            Result r = new Result();
            r.success = true;
            if (mode == 'outreach') {
                if (cr.taskResults.size() >= 2) r.qualificationReport = cr.taskResults[1].output;
                if (cr.taskResults.size() >= 3) r.agentEmail          = cr.taskResults[2].output;
            } else {
                if (cr.taskResults.size() >= 2) r.conversionSummary   = cr.taskResults[1].output;
                if (cr.taskResults.size() >= 3) r.agentEmail          = cr.taskResults[2].output;
            }
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
    private static FC_Tool emailTool()    { return FC_Tool.fromMCP(new SC_LogEmailTool()); }
    private static FC_Tool convertTool()  { return FC_Tool.fromMCP(new SC_ConvertLeadTool()); }

    // ─── Mode 1: Initial Outreach ─────────────────────────────────────────────

    /**
     * Researches the lead, qualifies it, and sends a personalised first-touch email.
     *
     * @param leadId  Salesforce Lead Id
     */
    public static Result outreach(Id leadId) {
        if (leadId == null) return new Result().error('leadId is required');

        // ── Agents ────────────────────────────────────────────────────────────
        FC_Agent researcher = new FC_Agent.Builder('Lead Researcher')
            .goal('Build a complete factual profile of the lead from Salesforce CRM data.')
            .backstory('You are a meticulous CRM analyst. You use QueryRecords to retrieve '
                + 'full lead info including activities and company context. You report only facts.')
            .tool(queryTool())
            .maxIterations(5)
            .build();

        FC_Agent qualifier = new FC_Agent.Builder('Lead Qualifier')
            .goal('Score the lead 1-10 and recommend: Prioritise, Nurture, or Disqualify. '
                + 'Identify the strongest buying signal and biggest risk.')
            .backstory('You are a B2B revenue ops specialist using BANT criteria. '
                + 'You are concise, evidence-based, and never score without citing a data point.')
            .build();

        FC_Agent outreachAgent = new FC_Agent.Builder('Outreach Specialist')
            .goal('Draft and send a personalised first-touch email that gets a reply. '
                + 'Use LogOutboundEmail to send the email once drafted.')
            .backstory('You are an elite SDR. Emails under 150 words, human tone, '
                + 'specific to the prospect\'s context. Never "I hope this finds you well." '
                + 'Always call LogOutboundEmail to deliver the email — do not just return it as text.')
            .tool(emailTool())
            .maxIterations(4)
            .build();

        // ── Tasks ─────────────────────────────────────────────────────────────
        FC_Task researchTask = new FC_Task.Builder('Research Lead')
            .description(
                'Use QueryRecords with these SOQL queries:\n'
                + '1. SELECT Id, FirstName, LastName, Title, Company, Industry, AnnualRevenue, '
                + '   NumberOfEmployees, LeadSource, Status, Email, Phone, Description, CreatedDate '
                + '   FROM Lead WHERE Id = \'' + leadId + '\'\n'
                + '2. SELECT Subject, Status, ActivityDate, Description FROM Task '
                + '   WHERE WhoId = \'' + leadId + '\' ORDER BY ActivityDate DESC LIMIT 5\n'
                + 'Report every field returned.'
            )
            .expectedOutput('Lead profile (all fields) plus recentActivities list.')
            .assignToAgent('Lead Researcher')
            .build();

        FC_Task qualifyTask = new FC_Task.Builder('Qualify Lead')
            .description('Based on the lead research, score this lead and decide whether to pursue, nurture, or disqualify. '
                + 'Always qualify leads with a valid email as at least "Nurture" unless clearly spam.')
            .expectedOutput('Score (1-10), grade (A/B/C/D), recommendation, and 3-bullet rationale.')
            .assignToAgent('Lead Qualifier')
            .withContext('Research Lead')
            .build();

        FC_Task emailTask = new FC_Task.Builder('Send Outreach Email')
            .description(
                'Draft and send a personalised outreach email to this lead.\n\n'
                + 'Requirements:\n'
                + '- Open with something specific about their company or industry\n'
                + '- Connect their business context to a relevant outcome you can help with\n'
                + '- One clear CTA (e.g. "Worth a 15-min call?")\n'
                + '- Under 150 words\n'
                + '- Include a subject line\n\n'
                + 'After composing the email, call LogOutboundEmail with:\n'
                + '  stage="Lead", leadId="' + leadId + '", direction=Outbound,\n'
                + '  agentName="Outreach Specialist",\n'
                + '  toEmail=<lead email from research>,\n'
                + '  subject=<your subject line>, body=<your email body>'
            )
            .expectedOutput('Confirmation that LogOutboundEmail was called. Include the full email text.')
            .assignToAgent('Outreach Specialist')
            .withContext('Research Lead')
            .withContext('Qualify Lead')
            .build();

        return runCrew('Lead Outreach Crew', researcher, qualifier, outreachAgent,
                       researchTask, qualifyTask, emailTask, 'outreach');
    }

    // ─── Mode 2: Handle Customer Reply ────────────────────────────────────────

    /**
     * Reads the conversation, crafts a contextual reply, and converts the lead if ready.
     *
     * @param leadId          Salesforce Lead Id
     * @param customerMessage The customer's inbound message text
     */
    public static Result handleReply(Id leadId, String customerMessage) {
        if (leadId == null)                    return new Result().error('leadId is required');
        if (String.isBlank(customerMessage))   return new Result().error('customerMessage is required');

        // ── Agents ────────────────────────────────────────────────────────────
        FC_Agent contextReader = new FC_Agent.Builder('Context Reader')
            .goal('Read the full conversation history and lead profile to understand '
                + 'the current state of this relationship.')
            .backstory('You are a sales analyst who reads every message carefully '
                + 'before advising on next steps. Use QueryRecords to read the lead record '
                + 'and the SC_ConversationMessage__c thread.')
            .tool(queryTool())
            .maxIterations(5)
            .build();

        FC_Agent strategist = new FC_Agent.Builder('Sales Strategist')
            .goal('Decide the best next action: respond with more info, ask a discovery question, '
                + 'or convert the lead if they have shown clear buying intent. '
                + 'The lead is ready to convert if they ask about pricing, timelines, or next steps.')
            .backstory('You are a senior enterprise AE. You read between the lines. '
                + 'You push deals forward without being pushy. '
                + 'Output your decision as: ACTION: RESPOND or ACTION: CONVERT, followed by reasoning.')
            .build();

        FC_Agent actionAgent = new FC_Agent.Builder('Sales Action Agent')
            .goal('Execute the strategist\'s decision: '
                + '(a) If RESPOND: craft a reply that moves the deal forward, then call LogOutboundEmail. '
                + '(b) If CONVERT: call ConvertLead to convert the lead, then call LogOutboundEmail '
                + '    to notify the customer about next steps.')
            .backstory('You are a deal executor. You always complete actions — never just plan them. '
                + 'For ConvertLead use opportunityName = "<Company> - AI Sales Platform". '
                + 'For LogOutboundEmail use stage="Lead" and leadId="' + leadId + '".')
            .tool(emailTool())
            .tool(convertTool())
            .maxIterations(6)
            .build();

        // ── Tasks ─────────────────────────────────────────────────────────────
        FC_Task readTask = new FC_Task.Builder('Read Context')
            .description(
                'The customer just replied to our outreach. Their message:\n\n'
                + '"' + customerMessage + '"\n\n'
                + 'Run these QueryRecords calls:\n'
                + '1. SELECT Id, FirstName, LastName, Email, Company, Status, IsConverted '
                + '   FROM Lead WHERE Id = \'' + leadId + '\'\n'
                + '2. SELECT Direction__c, Stage__c, Subject__c, Body__c, SentDate__c '
                + '   FROM SC_ConversationMessage__c WHERE LeadId__c = \'' + leadId
                + '\' ORDER BY SentDate__c ASC LIMIT 20'
            )
            .expectedOutput('Summary of lead profile + full conversation thread + customer\'s current sentiment.')
            .assignToAgent('Context Reader')
            .build();

        FC_Task strategyTask = new FC_Task.Builder('Choose Strategy')
            .description(
                'Based on the conversation context, decide: should we RESPOND with more info '
                + 'or CONVERT the lead now?\n\n'
                + 'Convert if the customer message contains: pricing questions, timeline questions, '
                + '"next steps", "interested", "move forward", "proposal", "contract", or similar signals.\n\n'
                + 'The customer\'s latest message: "' + customerMessage + '"'
            )
            .expectedOutput('ACTION: RESPOND or ACTION: CONVERT, plus a 2-3 sentence rationale. '
                + 'If RESPOND, include bullet points of what to cover in the reply. '
                + 'If CONVERT, include the opportunityName to use.')
            .assignToAgent('Sales Strategist')
            .withContext('Read Context')
            .build();

        FC_Task executeTask = new FC_Task.Builder('Execute Action')
            .description(
                'Execute the strategy decided in the previous step.\n\n'
                + 'If ACTION: RESPOND:\n'
                + '  1. Write a contextual reply (under 120 words, include a clear next step)\n'
                + '  2. Call LogOutboundEmail with stage="Lead", leadId="' + leadId + '"\n\n'
                + 'If ACTION: CONVERT:\n'
                + '  1. Call ConvertLead with leadId="' + leadId + '" and appropriate opportunityName\n'
                + '  2. Call LogOutboundEmail to send a follow-up email confirming next steps '
                + '     (mention you\'d like to discuss their requirements in more detail)\n'
            )
            .expectedOutput('Confirmation of actions taken. Include the full email text sent. '
                + 'If converted: include the new accountId, contactId, and opportunityId.')
            .assignToAgent('Sales Action Agent')
            .withContext('Read Context')
            .withContext('Choose Strategy')
            .build();

        return runCrew('Lead Response Crew', contextReader, strategist, actionAgent,
                       readTask, strategyTask, executeTask, 'reply');
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    private static Result runCrew(String crewName,
                                  FC_Agent a1, FC_Agent a2, FC_Agent a3,
                                  FC_Task t1, FC_Task t2, FC_Task t3,
                                  String mode) {
        try {
            FC_CrewResult crewResult = new FC_Crew.Builder(crewName)
                .agent(a1).agent(a2).agent(a3)
                .task(t1).task(t2).task(t3)
                .verbose(true)
                .failFast(true)
                .build()
                .kickoff();

            if (crewResult.success) {
                return new Result().ok(crewResult, mode);
            } else {
                return new Result().error(crewResult.errorMessage);
            }
        } catch (Exception e) {
            return new Result().error('SC_LeadCrew execution failed: ' + e.getMessage());
        }
    }
}
