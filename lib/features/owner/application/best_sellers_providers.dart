import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../models/product.dart';
import 'owner_product_providers.dart';

/// How the best-sellers list is ranked.
enum BestSellerMetric {
  revenue('By revenue'),
  units('By units sold');

  const BestSellerMetric(this.label);

  final String label;
}

final bestSellerMetricProvider = StateProvider<BestSellerMetric>(
  (ref) => BestSellerMetric.revenue,
);

/// How far back best-sellers and reorder suggestions look — long enough to smooth out one
/// slow or busy day, short enough that a product's velocity still reflects how it sells now.
const int bestSellersWindowDays = 30;

/// One product's totals over the window, aggregated from completed orders' line items —
/// `sales/{orderId}` carries only order-level totals, not per-product detail.
class ProductSalesStat {
  const ProductSalesStat({
    required this.productId,
    required this.productName,
    required this.unitsSold,
    required this.revenue,
  });

  final String productId;
  final String productName;
  final int unitsSold;
  final Money revenue;

  /// Average units sold per day over the window — the velocity a reorder suggestion is
  /// built on.
  double get unitsPerDay => unitsSold / bestSellersWindowDays;
}

/// Every product with at least one sale in the window, unsorted.
///
/// Counts both storefront and walk-in (POS) sales: a best-sellers list that only saw
/// storefront orders would be blind to whatever a cashier rings up most.
final productSalesStatsProvider = FutureProvider<List<ProductSalesStat>>((
  ref,
) async {
  final repo = ref.watch(orderRepositoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(const Duration(days: bestSellersWindowDays - 1));
  final to = today.add(const Duration(days: 1));

  final orders = await repo.fetchCompletedBetween(from, to);

  final unitsByProduct = <String, int>{};
  final revenueByProduct = <String, Money>{};
  final nameByProduct = <String, String>{};

  for (final order in orders) {
    for (final item in order.items) {
      if (item.productId.isEmpty) continue;
      unitsByProduct.update(
        item.productId,
        (units) => units + item.quantity,
        ifAbsent: () => item.quantity,
      );
      revenueByProduct.update(
        item.productId,
        (revenue) => revenue + item.lineTotal,
        ifAbsent: () => item.lineTotal,
      );
      nameByProduct[item.productId] = item.productName;
    }
  }

  return [
    for (final productId in unitsByProduct.keys)
      ProductSalesStat(
        productId: productId,
        productName: nameByProduct[productId]!,
        unitsSold: unitsByProduct[productId]!,
        revenue: revenueByProduct[productId]!,
      ),
  ];
});

/// [productSalesStatsProvider], ordered by the chosen [BestSellerMetric].
final rankedBestSellersProvider =
    Provider<AsyncValue<List<ProductSalesStat>>>((ref) {
      final metric = ref.watch(bestSellerMetricProvider);
      return ref.watch(productSalesStatsProvider).whenData((stats) {
        final sorted = [...stats];
        sorted.sort(
          metric == BestSellerMetric.revenue
              ? (a, b) => b.revenue.compareTo(a.revenue)
              : (a, b) => b.unitsSold.compareTo(a.unitsSold),
        );
        return sorted;
      });
    });

/// How many days of stock left counts as "running out soon enough to act on".
const int reorderDaysOfStockThreshold = 7;

/// How many days of stock a suggested order should cover.
const int reorderTargetDaysOfCover = 14;

/// A product selling faster than its stock on hand will keep up with.
class ReorderSuggestion {
  const ReorderSuggestion({
    required this.product,
    required this.unitsPerDay,
    required this.daysOfStockLeft,
    required this.suggestedQuantity,
  });

  final Product product;
  final double unitsPerDay;
  final double daysOfStockLeft;
  final int suggestedQuantity;
}

/// Active products whose current stock will not last [reorderDaysOfStockThreshold] days at
/// their recent selling pace, most urgent first.
final reorderSuggestionsProvider =
    Provider<AsyncValue<List<ReorderSuggestion>>>((ref) {
      final stats = ref.watch(productSalesStatsProvider);
      final catalog = ref.watch(ownerCatalogProvider);

      if (stats.hasError) {
        return AsyncValue.error(stats.error!, stats.stackTrace!);
      }
      if (catalog.hasError) {
        return AsyncValue.error(catalog.error!, catalog.stackTrace!);
      }
      if (!stats.hasValue || !catalog.hasValue) {
        return const AsyncValue.loading();
      }

      final statsById = {
        for (final stat in stats.value!) stat.productId: stat,
      };

      final suggestions = <ReorderSuggestion>[];
      for (final product in catalog.value!) {
        if (!product.isActive) continue;
        final stat = statsById[product.id];
        if (stat == null || stat.unitsPerDay <= 0) continue;

        final daysLeft = product.stockQuantity / stat.unitsPerDay;
        if (daysLeft >= reorderDaysOfStockThreshold) continue;

        final target = (stat.unitsPerDay * reorderTargetDaysOfCover).ceil();
        suggestions.add(
          ReorderSuggestion(
            product: product,
            unitsPerDay: stat.unitsPerDay,
            daysOfStockLeft: daysLeft,
            suggestedQuantity: math.max(1, target - product.stockQuantity),
          ),
        );
      }

      suggestions.sort((a, b) => a.daysOfStockLeft.compareTo(b.daysOfStockLeft));
      return AsyncValue.data(suggestions);
    });
