/**
 * SC_CreateOrderTool - Creates a Salesforce Order from a Closed Won Opportunity.
 *
 * Creates an Order with OrderItems mirroring the Opportunity's line items.
 * The Account linked to the Opportunity must exist. Order is created in Draft
 * status and then Activated.
 *
 * @group SalesCycle
 */
public with sharing class SC_CreateOrderTool implements FC_IMCPTool {

    public String getName() {
        return 'CreateOrder';
    }

    public String getDescription() {
        return 'Creates a Salesforce Order from a Closed Won Opportunity, '
            + 'copying all products as OrderItems. '
            + 'Call this after payment is confirmed to initiate fulfillment. '
            + 'Returns the Order Id and order number.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('opportunityId', FC_ToolParameter.TYPE_STRING)
                .description('The Closed Won Opportunity Id to create the order from')
                .required()
                .build(),
            new FC_ToolParameter.Builder('effectiveDate', FC_ToolParameter.TYPE_STRING)
                .description('Order effective date in YYYY-MM-DD format. Defaults to today.')
                .build(),
            new FC_ToolParameter.Builder('description', FC_ToolParameter.TYPE_STRING)
                .description('Order description or special instructions')
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String oppId         = (String) params.get('opportunityId');
            String effectiveDateS = (String) params.get('effectiveDate');
            String description   = (String) params.get('description');

            if (String.isBlank(oppId)) {
                return error('opportunityId is required');
            }

            Opportunity opp = [
                SELECT Id, Name, AccountId, Amount, Pricebook2Id, CloseDate, StageName
                FROM Opportunity WHERE Id = :oppId LIMIT 1
            ];

            if (opp.AccountId == null) {
                return error('Opportunity must have an Account before creating an Order.');
            }

            List<OpportunityLineItem> lineItems = [
                SELECT PricebookEntryId, Quantity, UnitPrice, Description, Product2.Name
                FROM OpportunityLineItem
                WHERE OpportunityId = :oppId
            ];
            if (lineItems.isEmpty()) {
                return error('No products on this opportunity. Cannot create an order without line items.');
            }

            Date effectiveDate = String.isNotBlank(effectiveDateS)
                ? Date.valueOf(effectiveDateS)
                : Date.today();

            Order ord = new Order(
                AccountId     = opp.AccountId,
                OpportunityId = oppId,
                Pricebook2Id  = opp.Pricebook2Id,
                EffectiveDate = effectiveDate,
                Status        = 'Draft',
                Description   = String.isNotBlank(description)
                    ? description
                    : 'Order for: ' + opp.Name
            );
            insert ord;

            // Add order items
            List<OrderItem> orderItems = new List<OrderItem>();
            for (OpportunityLineItem oli : lineItems) {
                orderItems.add(new OrderItem(
                    OrderId          = ord.Id,
                    PricebookEntryId = oli.PricebookEntryId,
                    Quantity         = oli.Quantity,
                    UnitPrice        = oli.UnitPrice,
                    Description      = oli.Description
                ));
            }
            insert orderItems;

            // Activate the order
            ord.Status = 'Activated';
            update ord;

            // Reload to get the order number
            Order activated = [SELECT Id, OrderNumber, Status FROM Order WHERE Id = :ord.Id LIMIT 1];

            List<Map<String, Object>> itemSummary = new List<Map<String, Object>>();
            for (OpportunityLineItem oli : lineItems) {
                itemSummary.add(new Map<String, Object>{
                    'product'   => oli.Product2.Name,
                    'quantity'  => oli.Quantity,
                    'unitPrice' => oli.UnitPrice
                });
            }

            return JSON.serialize(new Map<String, Object>{
                'success'      => true,
                'orderId'      => activated.Id,
                'orderNumber'  => activated.OrderNumber,
                'status'       => activated.Status,
                'lineItems'    => itemSummary,
                'message'      => 'Order ' + activated.OrderNumber + ' created and activated with '
                    + orderItems.size() + ' item(s).'
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
