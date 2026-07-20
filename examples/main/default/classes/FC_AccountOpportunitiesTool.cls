/**
 * FC_AccountOpportunitiesTool - Custom tool that returns Closed Won opportunity
 * totals grouped by Account for a given account name prefix.
 *
 * Demonstrates how to build a production-style FC_IMCPTool with real SOQL.
 *
 * @group ForceCrew
 */
public with sharing class FC_AccountOpportunitiesTool implements FC_IMCPTool {

    public String getName() {
        return 'GetAccountOpportunities';
    }

    public String getDescription() {
        return 'Returns Closed Won opportunity totals grouped by Account. '
            + 'Provide an account name prefix (e.g. "Acme") to filter results. '
            + 'Returns each account\'s name, total closed-won revenue, and deal count.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('accountPrefix', FC_ToolParameter.TYPE_STRING)
                .description('Account name prefix to filter by (uses LIKE match). Pass "%" for all accounts.')
                .required()
                .build(),
            new FC_ToolParameter.Builder('topN', FC_ToolParameter.TYPE_INTEGER)
                .description('Maximum number of accounts to return, ordered by revenue descending. Default: 10.')
                .defaultValue(10)
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String prefix = (String) params.get('accountPrefix');
            if (String.isBlank(prefix)) {
                return error('accountPrefix is required');
            }
            String likeValue = prefix.endsWith('%') ? prefix : prefix + '%';
            Integer topN = params.containsKey('topN')
                ? Integer.valueOf(String.valueOf(params.get('topN')))
                : 10;

            List<AggregateResult> rows = [
                SELECT Account.Name acctName,
                       SUM(Amount) totalRevenue,
                       COUNT(Id) dealCount
                FROM Opportunity
                WHERE StageName = 'Closed Won'
                  AND Account.Name LIKE :likeValue
                GROUP BY Account.Name
                ORDER BY SUM(Amount) DESC
                LIMIT :topN
            ];

            List<Map<String, Object>> accounts = new List<Map<String, Object>>();
            for (AggregateResult r : rows) {
                accounts.add(new Map<String, Object>{
                    'accountName'  => r.get('acctName'),
                    'totalRevenue' => r.get('totalRevenue'),
                    'dealCount'    => r.get('dealCount')
                });
            }

            return JSON.serialize(new Map<String, Object>{
                'success'  => true,
                'count'    => accounts.size(),
                'accounts' => accounts
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
