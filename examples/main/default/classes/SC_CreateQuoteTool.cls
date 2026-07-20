/**
 * SC_CreateQuoteTool - Creates a Salesforce Quote with line items copied from an Opportunity.
 *
 * Reads all OpportunityLineItems and mirrors them as QuoteLineItems on the new Quote.
 * Used by the Quote Agent to build a formal quote document for the customer.
 *
 * @group SalesCycle
 */
public with sharing class SC_CreateQuoteTool implements FC_IMCPTool {

    public String getName() {
        return 'CreateQuote';
    }

    public String getDescription() {
        return 'Creates a Salesforce Quote for an Opportunity, copying all products as line items. '
            + 'Returns the Quote Id and a summary of line items. '
            + 'Call this when the customer is ready to review formal pricing.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('opportunityId', FC_ToolParameter.TYPE_STRING)
                .description('The Opportunity Id to create the quote for')
                .required()
                .build(),
            new FC_ToolParameter.Builder('quoteName', FC_ToolParameter.TYPE_STRING)
                .description('Name for the quote (e.g. "Q-2025-Acme-AI-Platform"). Defaults to "Quote - <OppName>"')
                .build(),
            new FC_ToolParameter.Builder('expirationDays', FC_ToolParameter.TYPE_INTEGER)
                .description('Number of days until quote expires. Default: 30')
                .defaultValue(30)
                .build(),
            new FC_ToolParameter.Builder('description', FC_ToolParameter.TYPE_STRING)
                .description('Quote description or notes for the customer')
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String  oppId          = (String)  params.get('opportunityId');
            String  quoteName      = (String)  params.get('quoteName');
            Integer expirationDays = params.containsKey('expirationDays')
                ? Integer.valueOf(String.valueOf(params.get('expirationDays')))
                : 30;
            String  descStr        = (String)  params.get('description');

            if (String.isBlank(oppId)) {
                return error('opportunityId is required');
            }

            Opportunity opp = [
                SELECT Id, Name, AccountId, Pricebook2Id, Amount, CloseDate
                FROM Opportunity WHERE Id = :oppId LIMIT 1
            ];

            // Get line items
            List<OpportunityLineItem> lineItems = [
                SELECT PricebookEntryId, Quantity, UnitPrice, Description, Product2.Name
                FROM OpportunityLineItem
                WHERE OpportunityId = :oppId
            ];

            if (lineItems.isEmpty()) {
                return error('No products on this opportunity. Add products first using AddProductToOpportunity.');
            }

            String finalQuoteName = String.isNotBlank(quoteName)
                ? quoteName
                : 'Quote - ' + opp.Name;

            Quote q = new Quote(
                OpportunityId    = oppId,
                Name             = finalQuoteName,
                Pricebook2Id     = opp.Pricebook2Id,
                ExpirationDate   = Date.today().addDays(expirationDays),
                Description      = descStr,
                Status           = 'Draft'
            );
            insert q;

            // Copy line items to quote
            List<QuoteLineItem> qliList = new List<QuoteLineItem>();
            for (OpportunityLineItem oli : lineItems) {
                qliList.add(new QuoteLineItem(
                    QuoteId          = q.Id,
                    PricebookEntryId = oli.PricebookEntryId,
                    Quantity         = oli.Quantity,
                    UnitPrice        = oli.UnitPrice,
                    Description      = oli.Description
                ));
            }
            insert qliList;

            // Summary of products
            List<Map<String, Object>> lineItemSummary = new List<Map<String, Object>>();
            Decimal totalAmount = 0;
            for (OpportunityLineItem oli : lineItems) {
                Decimal lineTotal = oli.Quantity * oli.UnitPrice;
                totalAmount += lineTotal;
                lineItemSummary.add(new Map<String, Object>{
                    'product'    => oli.Product2.Name,
                    'quantity'   => oli.Quantity,
                    'unitPrice'  => oli.UnitPrice,
                    'lineTotal'  => lineTotal
                });
            }

            return JSON.serialize(new Map<String, Object>{
                'success'        => true,
                'quoteId'        => q.Id,
                'quoteName'      => q.Name,
                'expirationDate' => String.valueOf(q.ExpirationDate),
                'lineItems'      => lineItemSummary,
                'totalAmount'    => totalAmount,
                'message'        => 'Quote created with ' + qliList.size() + ' line item(s). Total: $' + totalAmount
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
