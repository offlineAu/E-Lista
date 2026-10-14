import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/sale.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../application/dashboard_providers.dart'
    show EstimatedWeekTrend, WeekBarPoint, estimatedWeekTrendProvider;

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
    final weekTrend = ref.watch(estimatedWeekTrendProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.ownerBestSellers),
            icon: const Icon(Icons.leaderboard_outlined),
            tooltip: 'Best sellers',
          ),
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
            ..invalidate(salesByDayProvider)
            ..invalidate(estimatedWeekTrendProvider);
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
            Text('This week', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            AsyncView<EstimatedWeekTrend>(
              value: weekTrend,
              compact: true,
              onRetry: () => ref.invalidate(estimatedWeekTrendProvider),
              builder: (context, trend) => GlassCard(
                child: Column(
                  children: [
                    _WeeklyBarChart(weekBars: trend.weekBars),
                    if (trend.weekBars.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      const _ChartLegend(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const _EstimateDisclosure(),
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
        _PaymentSplitBar(summary: summary),
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

/// Monday through Sunday of the current week — solid bars for days that have happened,
/// lighter outlined bars for the trailing-average projection of days still to come.
class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.weekBars});

  final List<WeekBarPoint> weekBars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (weekBars.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('No data yet')),
      );
    }

    final maxCentavos = weekBars
        .map((bar) => bar.value.centavos)
        .fold(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in weekBars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxCentavos <= 0
                              ? 0.03
                              : (bar.value.centavos / maxCentavos).clamp(
                                  0.03,
                                  1.0,
                                ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: bar.isProjected
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.18,
                                    )
                                  : theme.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                              border: bar.isProjected
                                  ? Border.all(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.5),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bar.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Distinguishes the solid "actual" bars from the dashed "estimated" ones, so the chart
/// reads correctly without having to already know the convention.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatchColor = theme.colorScheme.primary;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: swatchColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text('Actual', style: labelStyle),
        const SizedBox(width: 16),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: swatchColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: swatchColor.withValues(alpha: 0.5)),
          ),
        ),
        const SizedBox(width: 6),
        Text('Estimated', style: labelStyle),
      ],
    );
  }
}

/// Makes clear the lighter bars are a projection, not a recorded figure — the same
/// disclosure the concept canvas puts under its own trend chart.
class _EstimateDisclosure extends StatelessWidget {
  const _EstimateDisclosure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The lighter bars are an estimate — a 4-week trailing average, not '
              'a guarantee.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cash/GCash split as a single proportional bar, with a legend — the same figures the
/// two [_MethodCard]s show as exact amounts, here as a share.
class _PaymentSplitBar extends StatelessWidget {
  const _PaymentSplitBar({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCentavos =
        summary.cashGrossSales.centavos + summary.gcashGrossSales.centavos;
    if (totalCentavos <= 0) return const SizedBox.shrink();

    final cashFlex = ((summary.cashGrossSales.centavos / totalCentavos) * 1000)
        .round()
        .clamp(0, 1000);
    final gcashFlex = 1000 - cashFlex;
    final cashColor = theme.colorScheme.primary;
    final gcashColor = theme.colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                if (cashFlex > 0) Expanded(flex: cashFlex, child: ColoredBox(color: cashColor)),
                if (cashFlex > 0 && gcashFlex > 0) const SizedBox(width: 2),
                if (gcashFlex > 0) Expanded(flex: gcashFlex, child: ColoredBox(color: gcashColor)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LegendDot(color: cashColor, label: 'Cash'),
            const SizedBox(width: 16),
            _LegendDot(color: gcashColor, label: 'GCash'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
