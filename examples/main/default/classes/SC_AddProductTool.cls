/**
 * SC_AddProductTool - Adds a product (OpportunityLineItem) to an Opportunity.
 *
 * Automatically sets the Opportunity's Pricebook2 to the standard pricebook if not yet set.
 * Used by the Opportunity Agent after identifying which products match the customer's needs.
 *
 * @group SalesCycle
 */
public with sharing class SC_AddProductTool implements FC_IMCPTool {

    public String getName() {
        return 'AddProductToOpportunity';
    }

    public String getDescription() {
        return 'Adds a product to an Opportunity as a line item. '
            + 'Requires the PricebookEntryId from GetProductCatalog. '
            + 'Optionally override the unit price (e.g. for a negotiated rate). '
            + 'Returns the created OpportunityLineItem Id.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('opportunityId', FC_ToolParameter.TYPE_STRING)
                .description('The Opportunity Id to add the product to')
                .required()
                .build(),
            new FC_ToolParameter.Builder('pricebookEntryId', FC_ToolParameter.TYPE_STRING)
                .description('PricebookEntry Id from GetProductCatalog')
                .required()
                .build(),
            new FC_ToolParameter.Builder('quantity', FC_ToolParameter.TYPE_INTEGER)
                .description('Quantity to add. Default: 1')
                .defaultValue(1)
                .build(),
            new FC_ToolParameter.Builder('unitPrice', FC_ToolParameter.TYPE_NUMBER)
                .description('Override unit price. If not provided, uses the pricebook list price.')
                .build(),
            new FC_ToolParameter.Builder('description', FC_ToolParameter.TYPE_STRING)
                .description('Optional line item description or notes')
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String  oppId           = (String)  params.get('opportunityId');
            String  pbeId           = (String)  params.get('pricebookEntryId');
            Integer quantity        = params.containsKey('quantity')
                ? Integer.valueOf(String.valueOf(params.get('quantity')))
                : 1;
            String  descriptionStr  = (String)  params.get('description');

            if (String.isBlank(oppId) || String.isBlank(pbeId)) {
                return error('opportunityId and pricebookEntryId are required');
            }

            // Load the PricebookEntry to get the list price
            List<PricebookEntry> pbes = [
                SELECT Id, UnitPrice, Pricebook2Id, Product2.Name
                FROM PricebookEntry WHERE Id = :pbeId LIMIT 1
            ];
            if (pbes.isEmpty()) {
                return error('PricebookEntry not found: ' + pbeId);
            }
            PricebookEntry pbe = pbes[0];

            Decimal unitPrice = pbes[0].UnitPrice;
            if (params.containsKey('unitPrice') && params.get('unitPrice') != null) {
                unitPrice = Decimal.valueOf(String.valueOf(params.get('unitPrice')));
            }

            // Ensure the Opportunity has a Pricebook set
            Opportunity opp = [SELECT Id, Pricebook2Id FROM Opportunity WHERE Id = :oppId LIMIT 1];
            if (opp.Pricebook2Id == null) {
                opp.Pricebook2Id = pbe.Pricebook2Id;
                update opp;
            }

            OpportunityLineItem oli = new OpportunityLineItem(
                OpportunityId     = oppId,
                PricebookEntryId  = pbeId,
                Quantity          = quantity,
                UnitPrice         = unitPrice,
                Description       = descriptionStr
            );
            insert oli;

            return JSON.serialize(new Map<String, Object>{
                'success'               => true,
                'lineItemId'            => oli.Id,
                'productName'           => pbe.Product2.Name,
                'quantity'              => quantity,
                'unitPrice'             => unitPrice,
                'totalPrice'            => quantity * unitPrice,
                'message'               => pbe.Product2.Name + ' (qty ' + quantity + ' @ $' + unitPrice + ') added to opportunity.'
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
