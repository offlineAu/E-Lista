import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';
import 'payment_method.dart';

/// The financial record of a completed order, at `sales/{orderId}`.
///
/// Written by the server when an order moves to `completed`, keyed by the order id so a
/// double completion cannot produce two sales rows. Owner-readable only.
///
/// Every figure is stored rather than derived, because the products it refers to will
/// change price and cost afterwards. Recomputing last month's profit from today's costs
/// would produce a number that is confidently wrong.
@immutable
class Sale {
  const Sale({
    required this.orderId,
    required this.paymentMethod,
    required this.grossSales,
    required this.productCost,
    required this.convenienceFee,
    required this.itemCount,
    this.completedAt,
    this.customerId,
    this.cashierId,
  });

  /// Also the document id.
  final String orderId;

  final PaymentMethod paymentMethod;

  /// What the customer paid for the goods — the order subtotal, excluding any fee.
  final Money grossSales;

  /// What those goods cost the store, from the order's frozen cost snapshot.
  final Money productCost;

  /// The GCash convenience fee collected on this order, ₱0 for cash.
  ///
  /// This is money the customer paid on top of the goods. Whether it is profit depends on
  /// what the store is charged in return; see [netProfit].
  final Money convenienceFee;

  final int itemCount;

  final DateTime? completedAt;
  final String? customerId;

  /// Who rang this up at the counter — set for a walk-in sale, `null` for a storefront
  /// order (which has no cashier) and for any walk-in sale recorded before this field
  /// existed.
  final String? cashierId;

  /// Revenue minus what the goods cost. This is the margin on the merchandise itself and
  /// is directly comparable between cash and GCash orders.
  Money get grossProfit => grossSales - productCost;

  /// What the customer paid in total, goods plus fee.
  Money get totalCollected => grossSales + convenienceFee;

  /// Profit including the convenience fee as revenue.
  ///
  /// The fee is treated as recovering the cost of accepting GCash, so it is added in full.
  /// If the store is itself charged a transfer fee, that is a separate expense the app
  /// does not track — which is exactly why reports label this figure "estimated" and show
  /// [grossProfit] beside it.
  Money get netProfit => grossProfit + convenienceFee;

  bool get isGcash => paymentMethod == PaymentMethod.gcash;

  /// Margin on the goods, in basis points, or `null` when there was no revenue to divide
  /// by. Returned as basis points to stay in exact integers.
  int? get grossMarginBasisPoints {
    if (grossSales.centavos == 0) return null;
    return (grossProfit.centavos * 10000) ~/ grossSales.centavos;
  }

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'paymentMethod': paymentMethod.toJson(),
    'grossSalesCentavos': grossSales.centavos,
    'productCostCentavos': productCost.centavos,
    'grossProfitCentavos': grossProfit.centavos,
    'convenienceFeeCentavos': convenienceFee.centavos,
    'netProfitCentavos': netProfit.centavos,
    'itemCount': itemCount,
    'customerId': customerId,
    'cashierId': cashierId,
    'completedAt': completedAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(completedAt!),
    // Denormalised so daily/weekly/monthly reports can group without reading every
    // document's timestamp and converting it client-side.
    'dayKey': completedAt == null ? null : dayKeyFor(completedAt!),
  };

  static Sale fromFirestore(DocumentSnapshot<Map<String, Object?>> snapshot) =>
      Sale.fromJson(snapshot.id, snapshot.data() ?? const {});

  static Sale fromJson(String orderId, Map<String, Object?> json) => Sale(
    orderId: orderId,
    paymentMethod: PaymentMethod.fromJson(json['paymentMethod']),
    grossSales: Money.fromJson(json['grossSalesCentavos']),
    productCost: Money.fromJson(json['productCostCentavos']),
    convenienceFee: Money.fromJson(json['convenienceFeeCentavos']),
    itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
    customerId: json['customerId'] as String?,
    cashierId: json['cashierId'] as String?,
    completedAt: switch (json['completedAt']) {
      Timestamp() => (json['completedAt']! as Timestamp).toDate(),
      _ => null,
    },
  );

  /// `2026-08-09` in local time — the key daily reports group by.
  ///
  /// Local time on purpose: a store's day ends when it closes, not at UTC midnight.
  static String dayKeyFor(DateTime moment) {
    final local = moment.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  bool operator ==(Object other) => other is Sale && other.orderId == orderId;

  @override
  int get hashCode => orderId.hashCode;

  @override
  String toString() =>
      'Sale($orderId, ${paymentMethod.id}, gross: $grossSales, profit: $netProfit)';
}

/// Sales rolled up over a period, for the dashboard and the reports screens.
///
/// Computed from [Sale] rows rather than stored, so a corrected or cancelled sale is
/// reflected immediately. The row count is bounded by the query's date range.
@immutable
class SalesSummary {
  const SalesSummary({
    required this.orderCount,
    required this.itemCount,
    required this.grossSales,
    required this.productCost,
    required this.convenienceFees,
    required this.cashGrossSales,
    required this.gcashGrossSales,
    this.from,
    this.to,
  });

  static const SalesSummary empty = SalesSummary(
    orderCount: 0,
    itemCount: 0,
    grossSales: Money.zero,
    productCost: Money.zero,
    convenienceFees: Money.zero,
    cashGrossSales: Money.zero,
    gcashGrossSales: Money.zero,
  );

  final int orderCount;
  final int itemCount;

  final Money grossSales;
  final Money productCost;
  final Money convenienceFees;

  final Money cashGrossSales;
  final Money gcashGrossSales;

  final DateTime? from;
  final DateTime? to;

  /// Margin on the goods sold.
  Money get grossProfit => grossSales - productCost;

  /// Gross profit plus the convenience fees collected.
  Money get netProfit => grossProfit + convenienceFees;

  Money get totalCollected => grossSales + convenienceFees;

  bool get isEmpty => orderCount == 0;

  /// Average value of an order's goods, or ₱0 when there were no orders.
  Money get averageOrderValue => orderCount == 0
      ? Money.zero
      : Money.fromCentavos(grossSales.centavos ~/ orderCount);

  /// Builds a summary from the sales rows in a period.
  static SalesSummary summarise(
    Iterable<Sale> sales, {
    DateTime? from,
    DateTime? to,
  }) {
    var orderCount = 0;
    var itemCount = 0;
    var gross = Money.zero;
    var cost = Money.zero;
    var fees = Money.zero;
    var cash = Money.zero;
    var gcash = Money.zero;

    for (final sale in sales) {
      orderCount++;
      itemCount += sale.itemCount;
      gross += sale.grossSales;
      cost += sale.productCost;
      fees += sale.convenienceFee;
      if (sale.isGcash) {
        gcash += sale.grossSales;
      } else {
        cash += sale.grossSales;
      }
    }

    return SalesSummary(
      orderCount: orderCount,
      itemCount: itemCount,
      grossSales: gross,
      productCost: cost,
      convenienceFees: fees,
      cashGrossSales: cash,
      gcashGrossSales: gcash,
      from: from,
      to: to,
    );
  }

  @override
  String toString() =>
      'SalesSummary($orderCount orders, gross: $grossSales, net: $netProfit)';
}
