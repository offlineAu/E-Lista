import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/error_mapper.dart';
import '../models/sale.dart';

/// Reads `sales/{orderId}` — the financial record of completed orders.
///
/// Owner-only, and read-only from the client: a sale is written by the server when an
/// order is completed, keyed by the order id so completing twice cannot double-count.
///
/// Every query here is bounded by a date range. "All sales, ever" is a query that works
/// fine for the first month and then quietly becomes the slowest screen in the app.
class SalesRepository {
  SalesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'sales';

  CollectionReference<Map<String, Object?>> get _sales =>
      _firestore.collection(collectionPath);

  /// Sales completed within a half-open range `[from, to)`.
  Future<List<Sale>> fetchBetween(DateTime from, DateTime to) {
    return ErrorMapper.guard(() async {
      final snapshot = await _sales
          .where(
            'completedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from),
          )
          .where('completedAt', isLessThan: Timestamp.fromDate(to))
          .orderBy('completedAt', descending: true)
          .get();
      return snapshot.docs.map(Sale.fromFirestore).toList();
    }, operation: 'load sales');
  }

  /// Streams the sales for one day, keyed by the denormalised `dayKey` so the dashboard
  /// updates the moment an order is completed.
  Stream<List<Sale>> watchDay(DateTime day) {
    return _sales
        .where('dayKey', isEqualTo: Sale.dayKeyFor(day))
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Sale.fromFirestore).toList());
  }

  /// Today's sales, summarised for the dashboard.
  Stream<SalesSummary> watchTodaySummary() {
    final now = DateTime.now();
    return watchDay(now).map(
      (sales) => SalesSummary.summarise(
        sales,
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day + 1),
      ),
    );
  }

  /// A summary over an arbitrary range, for the reports screens.
  Future<SalesSummary> summariseBetween(DateTime from, DateTime to) async {
    final sales = await fetchBetween(from, to);
    return SalesSummary.summarise(sales, from: from, to: to);
  }

  /// Day-by-day summaries across a range, for a trend list or chart.
  ///
  /// One query for the whole range, grouped in memory — far cheaper than a query per day.
  Future<Map<String, SalesSummary>> summariseByDay(
    DateTime from,
    DateTime to,
  ) async {
    final sales = await fetchBetween(from, to);
    final grouped = <String, List<Sale>>{};

    for (final sale in sales) {
      final completedAt = sale.completedAt;
      if (completedAt == null) continue;
      grouped.putIfAbsent(Sale.dayKeyFor(completedAt), () => []).add(sale);
    }

    return {
      for (final entry in grouped.entries)
        entry.key: SalesSummary.summarise(entry.value),
    };
  }

  /// The most recent sales, for the "recent activity" list.
  Stream<List<Sale>> watchRecent({int limit = 10}) {
    return _sales
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Sale.fromFirestore).toList());
  }
}
