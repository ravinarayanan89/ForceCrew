/**
 * LeadOutreachCrew - A real-world multi-agent crew for lead research and personalised outreach.
 *
 * This crew demonstrates genuine multi-agent value:
 *   - Agent 1 (Lead Researcher)  — has tools, pulls CRM data about the lead
 *   - Agent 2 (Lead Scorer)      — no tools, reasons over research to score the lead
 *   - Agent 3 (Outreach Writer)  — no tools, drafts a personalised first-touch email
 *
 * Each agent does something the others genuinely cannot:
 *   data access → judgement → tone-matched writing
 *
 * Context flows automatically:
 *   Research output → Scorer → Writer (both prior outputs injected)
 *
 * Usage:
 *   LeadOutreachCrew.Result r = LeadOutreachCrew.run(leadId);
 *   System.debug(r.score);
 *   System.debug(r.email);
 *
 * @group ForceCrew
 */
public with sharing class LeadOutreachCrew {

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class Result {
        public String  researchSummary { get; private set; }
        public String  scoringReport   { get; private set; }
        public String  email           { get; private set; }
        public Boolean success         { get; private set; }
        public String  errorMessage    { get; private set; }

        private Result() {}

        public Result ok(FC_CrewResult crewResult) {
            Result r = new Result();
            r.success = true;
            // Task results in order: Research → Score → Email
            if (crewResult.taskResults.size() >= 1) r.researchSummary = crewResult.taskResults[0].output;
            if (crewResult.taskResults.size() >= 2) r.scoringReport   = crewResult.taskResults[1].output;
            if (crewResult.taskResults.size() >= 3) r.email           = crewResult.taskResults[2].output;
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
     * Runs the Lead Outreach Crew synchronously for a given Lead Id.
     * Use this from anonymous Apex, invocable actions, or small-batch jobs.
     *
     * @param leadId  The Id of the Lead to research, score, and write outreach for
     * @return        Result with researchSummary, scoringReport, and email
     */
    public static Result run(Id leadId) {
            if (leadId == null) {
            return new Result().error('leadId is required');
        }

        // ── Tools (existing built-in ForceCrew tools) ─────────────────────────
        FC_Tool describeTool = FC_Tool.fromMCP(new FC_SampleDescribeTool());
        FC_Tool queryTool    = FC_Tool.fromMCP(new FC_SampleSOQLTool());

        // ── Agent 1: Lead Researcher ──────────────────────────────────────────
        // Has both tools. Will describe the Lead object first, then query details
        // and related activities to build a complete picture of this lead.
        FC_Agent researcher = new FC_Agent.Builder('Lead Researcher')
            .goal('Build a complete, factual profile of the lead by querying Salesforce CRM data. '
                + 'Discover available fields first, then retrieve the lead record, '
                + 'any related activity history, and the parent account if linked.')
            .backstory('You are a meticulous Salesforce CRM analyst. '
                + 'You always use DescribeObject before querying to confirm field names exist. '
                + 'You surface engagement signals: recent activities, open tasks, lead source, '
                + 'industry, company size, and job title. You report facts only — no opinions.')
            .tool(describeTool)
            .tool(queryTool)
            .maxIterations(8)
            .build();

        // ── Agent 2: Lead Scorer ──────────────────────────────────────────────
        // No tools — pure reasoning from the researcher's output.
        // Scores the lead and explains why, referencing specific data points.
        FC_Agent scorer = new FC_Agent.Builder('Lead Scorer')
            .goal('Score the lead from 1–10 based on fit, engagement, and urgency signals. '
                + 'Reference specific data points from the research. Identify the single '
                + 'strongest buying signal and the single biggest risk or gap.')
            .backstory('You are a B2B revenue operations specialist. '
                + 'You score leads using a BANT-inspired framework: Budget signals, '
                + 'Authority (is the title a decision-maker?), Need (industry/company context), '
                + 'and Timing (activity recency). You are direct and evidence-based. '
                + 'A score without data to back it up is worthless.')
            .build();

        // ── Agent 3: Outreach Writer ──────────────────────────────────────────
        // No tools — uses both prior outputs to draft a personalised email.
        FC_Agent writer = new FC_Agent.Builder('Outreach Writer')
            .goal('Write a personalised, concise first-touch outreach email that will get a reply. '
                + 'Reference the lead by first name, mention something specific about their '
                + 'company or role, and end with one clear low-friction call to action.')
            .backstory('You are an elite enterprise sales development rep. '
                + 'You write emails that are under 150 words, sound human (not templated), '
                + 'and open with insight about the prospect — not about your product. '
                + 'You never start with "I hope this email finds you well." '
                + 'Subject lines are under 8 words and curiosity-driven.')
            .build();

        // ── Task 1: Research the Lead ─────────────────────────────────────────
        FC_Task researchTask = new FC_Task.Builder('Research Lead')
            .description(
                'Research the Salesforce Lead with Id: ' + leadId + '.\n\n'
                + 'Steps:\n'
                + '1. Use DescribeObject on "Lead" to confirm available field names.\n'
                + '2. Query the Lead record — include: FirstName, LastName, Title, Company, '
                + '   Industry, AnnualRevenue, NumberOfEmployees, LeadSource, Status, '
                + '   Email, Phone, CreatedDate, LastModifiedDate, ConvertedDate, '
                + '   IsConverted, OwnerId.\n'
                + '3. Query open Tasks related to this lead: '
                + '   SELECT Subject, Status, ActivityDate, Description FROM Task '
                + '   WHERE WhoId = \'' + leadId + '\' ORDER BY ActivityDate DESC LIMIT 5.\n'
                + '4. If the lead has a Company name, query similar accounts: '
                + '   SELECT Name, Industry, AnnualRevenue, NumberOfEmployees FROM Account '
                + '   WHERE Name LIKE \'%<company>%\' LIMIT 3.'
            )
            .expectedOutput(
                'A structured JSON object with:\n'
                + '- lead: { firstName, lastName, title, company, industry, annualRevenue, '
                + '  numberOfEmployees, leadSource, status, email, createdDate }\n'
                + '- recentActivities: [ { subject, status, activityDate } ]\n'
                + '- accountMatches: [ { name, industry, annualRevenue } ]\n'
                + '- engagementSignals: string — a 2-3 sentence summary of engagement indicators'
            )
            .assignToAgent('Lead Researcher')
            .build();

        // ── Task 2: Score the Lead ────────────────────────────────────────────
        FC_Task scoreTask = new FC_Task.Builder('Score Lead')
            .description(
                'Based on the lead research, score this lead and explain your reasoning.\n\n'
                + 'Scoring criteria:\n'
                + '- Title/seniority (decision-maker vs. influencer vs. unknown)\n'
                + '- Company size and revenue signals\n'
                + '- Industry fit\n'
                + '- Lead source quality\n'
                + '- Activity recency and volume\n'
                + '- Time since lead creation (fresh vs. stale)\n\n'
                + 'Be explicit: if a data point is missing, flag it as a gap.'
            )
            .expectedOutput(
                'A scoring report with:\n'
                + '- score: integer 1–10\n'
                + '- grade: A/B/C/D\n'
                + '- strongestSignal: one sentence on the best buying indicator\n'
                + '- biggestGap: one sentence on the most concerning unknown\n'
                + '- recommendation: "Prioritise" / "Nurture" / "Disqualify"\n'
                + '- rationale: 3–5 bullet points, each referencing a specific data point'
            )
            .assignToAgent('Lead Scorer')
            .withContext('Research Lead')
            .build();

        // ── Task 3: Write Outreach Email ──────────────────────────────────────
        FC_Task emailTask = new FC_Task.Builder('Write Outreach Email')
            .description(
                'Draft a personalised first-touch outreach email for this lead.\n\n'
                + 'Requirements:\n'
                + '- Open with something specific to their company, industry, or role — not a generic opener\n'
                + '- Connect their context to a relevant outcome you can help with (do not name a product)\n'
                + '- End with ONE low-friction CTA (e.g., "Worth a 15-min call this week?")\n'
                + '- Under 150 words in the body\n'
                + '- Include a subject line\n\n'
                + 'Only write the email if the lead score is C or above. '
                + 'If the lead is graded D, write a short nurture note instead.'
            )
            .expectedOutput(
                'The outreach email formatted as:\n'
                + 'SUBJECT: <subject line>\n\n'
                + 'Hi <FirstName>,\n\n'
                + '<body>\n\n'
                + '<sign-off>'
            )
            .assignToAgent('Outreach Writer')
            .withContext('Research Lead')
            .withContext('Score Lead')
            .build();

        // ── Assemble and Run the Crew ─────────────────────────────────────────
        try {
            FC_CrewResult crewResult = new FC_Crew.Builder('Lead Outreach Crew')
                .agent(researcher)
                .agent(scorer)
                .agent(writer)
                .task(researchTask)
                .task(scoreTask)
                .task(emailTask)
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
            return new Result().error('Crew execution failed: ' + e.getMessage());
        }
    }
}
