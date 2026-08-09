import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/sale.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';

/// The period a report covers.
enum ReportPeriod {
  today('Today'),
  week('Last 7 days'),
  month('This month'),
  quarter('Last 90 days');

  const ReportPeriod(this.label);

  final String label;

  /// The half-open range `[from, to)` in local time.
  ///
  /// Local, not UTC: a store's day ends when it closes, and a report that cuts over at
  /// eight in the morning would be worse than useless.
  (DateTime, DateTime) rangeFrom(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    return switch (this) {
      ReportPeriod.today => (startOfToday, endOfToday),
      ReportPeriod.week => (
        startOfToday.subtract(const Duration(days: 6)),
        endOfToday,
      ),
      ReportPeriod.month => (DateTime(now.year, now.month), endOfToday),
      ReportPeriod.quarter => (
        startOfToday.subtract(const Duration(days: 89)),
        endOfToday,
      ),
    };
  }
}

final selectedReportPeriodProvider = StateProvider<ReportPeriod>(
  (ref) => ReportPeriod.today,
);

/// Sales in the selected period, summarised.
final salesSummaryProvider = FutureProvider<SalesSummary>((ref) async {
  final period = ref.watch(selectedReportPeriodProvider);
  final (from, to) = period.rangeFrom(DateTime.now());
  return ref.watch(salesRepositoryProvider).summariseBetween(from, to);
});

/// Day-by-day totals in the selected period, newest first.
final salesByDayProvider = FutureProvider<List<MapEntry<String, SalesSummary>>>(
  (ref) async {
    final period = ref.watch(selectedReportPeriodProvider);
    final (from, to) = period.rangeFrom(DateTime.now());
    final byDay = await ref
        .watch(salesRepositoryProvider)
        .summariseByDay(from, to);
    final entries = byDay.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  },
);

/// What the store took and what it kept, over a period the owner chooses.
///
/// Every figure is labelled for what it actually is. "Profit" here is the margin on goods
/// plus the convenience fees collected — it is not a full profit and loss, because the app
/// does not know the store's rent, its electricity, or what GCash charges for a transfer.
/// Calling an estimate an exact figure would be the most damaging thing this screen could
/// do.
class OwnerSalesScreen extends ConsumerWidget {
  const OwnerSalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final period = ref.watch(selectedReportPeriodProvider);
    final summary = ref.watch(salesSummaryProvider);
    final byDay = ref.watch(salesByDayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.ownerReports),
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Reports',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(salesSummaryProvider)
            ..invalidate(salesByDayProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in ReportPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(option.label),
                        selected: period == option,
                        onSelected: (_) =>
                            ref
                                    .read(selectedReportPeriodProvider.notifier)
                                    .state =
                                option,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AsyncView<SalesSummary>(
              value: summary,
              onRetry: () => ref.invalidate(salesSummaryProvider),
              builder: (context, value) => _SummaryCards(summary: value),
            ),
            const SizedBox(height: 28),
            Text('Day by day', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            AsyncView<List<MapEntry<String, SalesSummary>>>(
              value: byDay,
              compact: true,
              onRetry: () => ref.invalidate(salesByDayProvider),
              builder: (context, days) {
                if (days.isEmpty) {
                  return const EmptyView(
                    compact: true,
                    icon: Icons.insights_outlined,
                    title: 'No sales in this period',
                    message:
                        'Completed orders appear here as soon as you mark '
                        'them done.',
                  );
                }
                return Column(
                  children: [
                    for (final day in days)
                      _DayRow(dayKey: day.key, summary: day.value),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                PriceRow(
                  label: 'Sales',
                  amount: summary.grossSales,
                  note:
                      '${summary.orderCount} '
                      '${summary.orderCount == 1 ? 'order' : 'orders'} · '
                      '${summary.itemCount} items',
                ),
                PriceRow(
                  label: 'What those goods cost you',
                  amount: summary.productCost,
                ),
                const Divider(height: 20),
                PriceRow(
                  label: 'Margin on goods',
                  amount: summary.grossProfit,
                  amountColor: summary.grossProfit.isNegative
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                PriceRow(
                  label: 'GCash fees collected',
                  amount: summary.convenienceFees,
                ),
                const Divider(height: 20),
                PriceRow(
                  label: 'Estimated profit',
                  amount: summary.netProfit,
                  emphasised: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Estimated profit is your margin on goods plus the GCash fees you '
            'collected. It does not include rent, electricity, or what GCash '
            'charges you for transfers.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MethodCard(
                label: 'Cash',
                amount: summary.cashGrossSales.format(),
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MethodCard(
                label: 'GCash',
                amount: summary.gcashGrossSales.format(),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.label,
    required this.amount,
    required this.icon,
  });

  final String label;
  final String amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(label, style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.dayKey, required this.summary});

  final String dayKey;
  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = DateTime.tryParse(dayKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parsed == null
                        ? dayKey
                        : DateFormat('EEE d MMM').format(parsed),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '${summary.orderCount} '
                    '${summary.orderCount == 1 ? 'order' : 'orders'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  summary.grossSales.format(),
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${summary.netProfit.format()} profit',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
