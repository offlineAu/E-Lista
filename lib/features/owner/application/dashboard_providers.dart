import 'package:flutter_riverpod/flutter_riverpod.dart';

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
