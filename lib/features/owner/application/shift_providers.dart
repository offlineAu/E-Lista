import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../models/payment_method.dart';
import '../../auth/application/auth_controller.dart';

/// One cashier's walk-in sales today — what should be in the drawer, and what they should
/// have handled in GCash.
///
/// Reads `orders`, never `sales`: a cashier can already list orders (their prices and
/// totals, no cost or profit), and `sales/` documents carry the cost/profit figures a
/// cashier must never see. Everything a shift summary needs is on the order itself.
class ShiftCashSummary {
  const ShiftCashSummary({
    required this.expectedCash,
    required this.cashSalesCount,
    required this.gcashCollected,
    required this.gcashSalesCount,
    required this.itemCount,
  });

  static const ShiftCashSummary empty = ShiftCashSummary(
    expectedCash: Money.zero,
    cashSalesCount: 0,
    gcashCollected: Money.zero,
    gcashSalesCount: 0,
    itemCount: 0,
  );

  /// What today's cash walk-in sales should have added to the drawer.
  final Money expectedCash;
  final int cashSalesCount;

  /// What today's GCash walk-in sales collected — never physically in the drawer, shown
  /// only for context.
  final Money gcashCollected;
  final int gcashSalesCount;

  /// Items rung up across every walk-in sale this shift, cash and GCash alike.
  final int itemCount;

  int get salesCount => cashSalesCount + gcashSalesCount;

  /// Everything rung up this shift, cash and GCash together — not just what should be in
  /// the drawer.
  Money get totalRungUp => expectedCash + gcashCollected;
}

/// Today's shift summary for whoever is signed in.
final todaysShiftSummaryProvider = FutureProvider<ShiftCashSummary>((
  ref,
) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return ShiftCashSummary.empty;

  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final endOfToday = startOfToday.add(const Duration(days: 1));

  final orders = await ref
      .watch(orderRepositoryProvider)
      .fetchCompletedBetween(startOfToday, endOfToday);

  var expectedCash = Money.zero;
  var cashCount = 0;
  var gcashCollected = Money.zero;
  var gcashCount = 0;
  var itemCount = 0;

  for (final order in orders) {
    if (!order.isWalkIn || order.cashierId != session.uid) continue;
    itemCount += order.itemCount;
    if (order.paymentMethod == PaymentMethod.cash) {
      expectedCash += order.total;
      cashCount++;
    } else {
      gcashCollected += order.total;
      gcashCount++;
    }
  }

  return ShiftCashSummary(
    expectedCash: expectedCash,
    cashSalesCount: cashCount,
    gcashCollected: gcashCollected,
    gcashSalesCount: gcashCount,
    itemCount: itemCount,
  );
});
