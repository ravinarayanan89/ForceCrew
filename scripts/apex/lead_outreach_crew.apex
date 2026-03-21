// ═══════════════════════════════════════════════════════════════════════════
// ForceCrew — Lead Outreach Crew  |  Anonymous Apex Test Script
//
// What this crew does:
//   Agent 1 — Lead Researcher  (tools: DescribeObject + QueryRecords)
//             Describes the Lead object, queries the lead record,
//             related Tasks, and any matching Accounts.
//
//   Agent 2 — Lead Scorer      (no tools — pure reasoning)
//             Reads the research and scores the lead 1–10 using BANT signals.
//             Identifies the strongest buying signal and biggest gap.
//
//   Agent 3 — Outreach Writer  (no tools — pure writing)
//             Reads the score + research and writes a personalised
//             first-touch email under 150 words.
//
// Context flows:  Research → Scorer  (gets research output)
//                 Research → Writer  (gets research + score output)
//
// How to run:
//   Developer Console → Debug → Open Execute Anonymous Window → paste → Execute
//   Then open Logs, filter on USER_DEBUG to see the full ReAct trace.
// ═══════════════════════════════════════════════════════════════════════════

// ── Step 1: Pick a real Lead from your org ──────────────────────────────────
// Grab the first open Lead — swap in a specific Id if you have one in mind.
List<Lead> leads = [
    SELECT Id, FirstName, LastName, Company, Title
    FROM   Lead
    WHERE  IsConverted = false
    LIMIT  1
];

if (leads.isEmpty()) {
    System.debug('⚠  No open Leads found in this org. Create a Lead first, then re-run.');
    return;
}

Lead lead = leads[0];
System.debug('══ Running Lead Outreach Crew for: '
    + lead.FirstName + ' ' + lead.LastName
    + ' | ' + lead.Title
    + ' @ ' + lead.Company
    + ' [' + lead.Id + ']');

// ── Step 2: Run the crew ────────────────────────────────────────────────────
Long startMs = System.currentTimeMillis();

LeadOutreachCrew.Result result = LeadOutreachCrew.run(lead.Id);

Long elapsed = System.currentTimeMillis() - startMs;

// ── Step 3: Print results ───────────────────────────────────────────────────
System.debug('\n══════════════════════════════════════════');
System.debug('SUCCESS: ' + result.success + '  |  Time: ' + elapsed + 'ms');
System.debug('══════════════════════════════════════════');

if (!result.success) {
    System.debug('ERROR: ' + result.errorMessage);
} else {
    System.debug('\n── AGENT 1 OUTPUT: Research Summary ──────');
    System.debug(result.researchSummary);

    System.debug('\n── AGENT 2 OUTPUT: Lead Score & Report ───');
    System.debug(result.scoringReport);

    System.debug('\n── AGENT 3 OUTPUT: Outreach Email ─────────');
    System.debug(result.email);
}
