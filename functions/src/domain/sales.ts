/**
 * Profit arithmetic for a completed sale.
 *
 * Pure, so `updateOrderStatus`'s completed branch and `placeWalkInSale` compute the same
 * numbers the same way instead of each re-deriving gross/net profit inline.
 */

export interface SaleFinancials {
  grossSalesCentavos: number;
  productCostCentavos: number;
  convenienceFeeCentavos: number;
}

export interface SaleProfit {
  grossProfitCentavos: number;
  netProfitCentavos: number;
}

/**
 * `grossProfit = grossSales - productCost`; `netProfit = grossProfit + convenienceFee`.
 *
 * The fee is money the customer paid on top of the goods, counted as revenue here. What the
 * store is charged by GCash in return is an expense this app does not see, which is why
 * reports call this "estimated" — this function just does the addition consistently
 * wherever a sale's profit is computed.
 */
export function computeSaleProfit(input: SaleFinancials): SaleProfit {
  const grossProfitCentavos = input.grossSalesCentavos - input.productCostCentavos;
  return {
    grossProfitCentavos,
    netProfitCentavos: grossProfitCentavos + input.convenienceFeeCentavos,
  };
}
