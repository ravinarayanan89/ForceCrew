/**
 * SC_ApplyDiscountTool - Applies a percentage discount to all line items on a Quote.
 *
 * Used by the Quote Agent during negotiation when the customer requests a price reduction.
 * Updates each QuoteLineItem's Discount field and recalculates the effective unit price.
 *
 * @group SalesCycle
 */
public with sharing class SC_ApplyDiscountTool implements FC_IMCPTool {

    public String getName() {
        return 'ApplyQuoteDiscount';
    }

    public String getDescription() {
        return 'Applies a percentage discount to all line items on a Quote. '
            + 'Use this during negotiation when the customer requests a lower price. '
            + 'Returns the updated totals after discount is applied.';
    }

    public List<FC_ToolParameter> getParameters() {
        return new List<FC_ToolParameter>{
            new FC_ToolParameter.Builder('quoteId', FC_ToolParameter.TYPE_STRING)
                .description('The Quote Id to apply the discount to')
                .required()
                .build(),
            new FC_ToolParameter.Builder('discountPercent', FC_ToolParameter.TYPE_NUMBER)
                .description('Discount percentage to apply (e.g. 10 for 10% off). Maximum: 50')
                .required()
                .build(),
            new FC_ToolParameter.Builder('reason', FC_ToolParameter.TYPE_STRING)
                .description('Reason for the discount (stored in the quote description)')
                .build()
        };
    }

    public String execute(Map<String, Object> params) {
        try {
            String  quoteId  = (String) params.get('quoteId');
            String  reason   = (String) params.get('reason');
            Decimal discount = params.containsKey('discountPercent')
                ? Decimal.valueOf(String.valueOf(params.get('discountPercent')))
                : null;

            if (String.isBlank(quoteId) || discount == null) {
                return error('quoteId and discountPercent are required');
            }
            if (discount < 0 || discount > 50) {
                return error('discountPercent must be between 0 and 50');
            }

            List<QuoteLineItem> qlis = [
                SELECT Id, Quantity, UnitPrice, Discount, Product2Id
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
            ];
            if (qlis.isEmpty()) {
                return error('No line items found on quote: ' + quoteId);
            }

            Decimal originalTotal  = 0;
            Decimal discountedTotal = 0;
            for (QuoteLineItem qli : qlis) {
                originalTotal += qli.Quantity * qli.UnitPrice;
                qli.Discount = discount;
                discountedTotal += qli.Quantity * qli.UnitPrice * (1 - discount / 100);
            }
            update qlis;

            // Update quote description with discount note
            if (String.isNotBlank(reason)) {
                Quote q = [SELECT Id, Description FROM Quote WHERE Id = :quoteId LIMIT 1];
                q.Description = (q.Description ?? '') + '\nDiscount applied: ' + discount + '% — ' + reason;
                update q;
            }

            return JSON.serialize(new Map<String, Object>{
                'success'         => true,
                'quoteId'         => quoteId,
                'discountPercent' => discount,
                'originalTotal'   => originalTotal,
                'discountedTotal' => discountedTotal.setScale(2),
                'savings'         => (originalTotal - discountedTotal).setScale(2),
                'message'         => discount + '% discount applied. New total: $' + discountedTotal.setScale(2)
            });

        } catch (Exception e) {
            return error(e.getMessage());
        }
    }

    private String error(String msg) {
        return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => msg });
    }
}
