import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../models/order.dart';
import '../../../models/product.dart';
import '../../../models/sale.dart';

/// The four figures on the owner's dashboard, each from its own stream.
///
/// Separate providers rather than one combined object: they update at different rates and
/// fail independently, so a Firestore hiccup on the sales query should not blank out the
/// low-stock list the owner was reading.

/// Today's sales and profit, recomputed as orders complete.
final todaySalesProvider = StreamProvider<SalesSummary>((ref) {
  return ref.watch(salesRepositoryProvider).watchTodaySummary();
});

/// Orders waiting to be confirmed.
final pendingOrderCountProvider = StreamProvider<int>((ref) {
  return ref.watch(orderRepositoryProvider).watchPendingCount();
});

/// Every order that is not yet completed or cancelled, for the owner's queue.
final openOrdersProvider = StreamProvider<List<StoreOrder>>((ref) {
  return ref.watch(orderRepositoryProvider).watchOpenOrders();
});

/// Products at or below their low-stock threshold, lowest first.
final lowStockProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchLowStock();
});

/// The most recent stock movements, for the inventory screen's activity feed.
final recentInventoryProvider = StreamProvider((ref) {
  return ref.watch(inventoryRepositoryProvider).watchRecent();
});

/// The latest completed sales, for the dashboard's recent-activity list.
final recentSalesProvider = StreamProvider<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).watchRecent();
});

/// A rough projection of this week's total sales, plus enough daily history for a
/// sparkline.
///
/// **Methodology, stated plainly because a wrong-looking number here is worse than no
/// number:** each weekday's remaining total is that weekday's average over the last 4
/// completed weeks. This is a trailing average, not a forecast that knows about a coming
/// payday or a holiday. [projectedTotal] is actual sales so far this week plus the average
/// for each weekday still to come.
class EstimatedWeekTrend {
  const EstimatedWeekTrend({
    required this.actualSoFar,
    required this.projectedTotal,
    required this.sparkline,
    required this.weekBars,
  });

  static const EstimatedWeekTrend empty = EstimatedWeekTrend(
    actualSoFar: Money.zero,
    projectedTotal: Money.zero,
    sparkline: [],
    weekBars: [],
  );

  final Money actualSoFar;
  final Money projectedTotal;

  /// Gross sales for the last 7 days, oldest first.
  final List<Money> sparkline;

  /// Monday through Sunday of the current week, actual where the day has happened,
  /// projected (that weekday's trailing average) where it has not.
  final List<WeekBarPoint> weekBars;
}

/// One bar of the current week's chart. Exactly one of [actual]/[projected] is the value to
/// show — [actual] once the day has happened, [projected] while it is still to come.
class WeekBarPoint {
  const WeekBarPoint({
    required this.label,
    required this.actual,
    required this.projected,
  });

  final String label;
  final Money? actual;
  final Money projected;

  bool get isProjected => actual == null;
  Money get value => actual ?? projected;
}

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

final estimatedWeekTrendProvider = FutureProvider<EstimatedWeekTrend>((
  ref,
) async {
  final repo = ref.watch(salesRepositoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // The 4 weeks before today, to build each weekday's trailing average.
  final historyFrom = today.subtract(const Duration(days: 28));
  final byDay = await repo.summariseByDay(
    historyFrom,
    today.add(const Duration(days: 1)),
  );

  final totalsByWeekday = <int, Money>{};
  final countsByWeekday = <int, int>{};
  for (final entry in byDay.entries) {
    final date = DateTime.parse(entry.key);
    totalsByWeekday.update(
      date.weekday,
      (total) => total + entry.value.grossSales,
      ifAbsent: () => entry.value.grossSales,
    );
    countsByWeekday.update(
      date.weekday,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  Money averageFor(int weekday) {
    final count = countsByWeekday[weekday];
    final total = totalsByWeekday[weekday];
    if (count == null || total == null || count == 0) return Money.zero;
    return Money.fromCentavos((total.centavos / count).round());
  }

  final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

  final weekBars = [
    for (var i = 0; i < 7; i++)
      _weekBarFor(startOfWeek.add(Duration(days: i)), today, byDay, averageFor),
  ];

  var actualSoFar = Money.zero;
  var projectedRemaining = Money.zero;
  for (final bar in weekBars) {
    if (bar.actual != null) {
      actualSoFar += bar.actual!;
    } else {
      projectedRemaining += bar.projected;
    }
  }

  final sparkline = [
    for (var i = 6; i >= 0; i--)
      byDay[Sale.dayKeyFor(today.subtract(Duration(days: i)))]?.grossSales ??
          Money.zero,
  ];

  return EstimatedWeekTrend(
    actualSoFar: actualSoFar,
    projectedTotal: actualSoFar + projectedRemaining,
    sparkline: sparkline,
    weekBars: weekBars,
  );
});

WeekBarPoint _weekBarFor(
  DateTime day,
  DateTime today,
  Map<String, SalesSummary> byDay,
  Money Function(int weekday) averageFor,
) {
  final hasHappened = !day.isAfter(today);
  return WeekBarPoint(
    label: _weekdayLabels[day.weekday - 1],
    actual: hasHappened ? (byDay[Sale.dayKeyFor(day)]?.grossSales ?? Money.zero) : null,
    projected: averageFor(day.weekday),
  );
}
