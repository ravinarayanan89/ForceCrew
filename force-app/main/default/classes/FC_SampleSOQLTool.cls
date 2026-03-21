/**
 * FC_SampleSOQLTool - A sample FC_IMCPTool that executes SOQL queries.
 *
 * Demonstrates how to implement FC_IMCPTool to create a self-describing tool
 * for use with ForceCrew agents. Register it with:
 *
 *   FC_Tool tool = FC_Tool.fromMCP(new FC_SampleSOQLTool());
 *
 * Security: Appends LIMIT 200 if the query has no LIMIT clause.
 *
 * @group ForceCrew
 */
public with sharing class FC_SampleSOQLTool implements FC_IMCPTool {

    private static final Integer MAX_RECORDS = 200;

    // ─── FC_IMCPTool ──────────────────────────────────────────────────────────

    public String getName() {
        return 'QueryRecords';
    }

    public String getDescription() {
        return 'Executes a SOQL query and returns matching Salesforce records as JSON. '
            + 'Use this tool to retrieve records before analysing or summarising data. '
            + 'Always include the fields you need in the SELECT clause.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('query', FC_ToolParameter.TYPE_STRING)
                .description(
                    'A valid SOQL query string. '
                    + 'Example: SELECT Id, Name, AnnualRevenue FROM Account ORDER BY AnnualRevenue DESC LIMIT 10'
                )
                .required()
                .build()
        };
    }

    // ─── FC_ITool ─────────────────────────────────────────────────────────────

    public String execute(Map<String, Object> params) {
        String query = (String) params.get('query');

        if (String.isBlank(query)) {
            return errorResult('Parameter "query" is required.');
        }

        try {
            // Append safety LIMIT if none provided
            if (!query.toLowerCase().contains(' limit ')) {
                query += ' LIMIT ' + MAX_RECORDS;
            }

            List<SObject> records = Database.query(query);

            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (SObject record : records) {
                results.add(record.getPopulatedFieldsAsMap());
            }

            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'count'   => records.size(),
                'records' => results
            });

        } catch (Exception e) {
            return errorResult(e.getMessage());
        }
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    private String errorResult(String message) {
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'error'   => message
        });
    }
}
