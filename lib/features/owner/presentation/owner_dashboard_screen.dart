import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../models/product.dart';
import '../../../models/sale.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/dashboard_providers.dart';

/// The owner's morning screen: what sold today, what is waiting, what is running out.
///
/// Four figures and four actions. The temptation with a dashboard is to show everything
/// available; what a shopkeeper actually needs before opening is whether there are orders
/// to pack and what to reorder.
class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(currentSessionProvider);
    final sales = ref.watch(todaySalesProvider);
    final pending = ref.watch(pendingOrderCountProvider);
    final lowStock = ref.watch(lowStockProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(todaySalesProvider)
            ..invalidate(pendingOrderCountProvider)
            ..invalidate(lowStockProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dashboard', style: theme.textTheme.headlineSmall),
                        Text(
                          session == null
                              ? 'Your store today'
                              : '${session.greetingName}, here is your store today',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.go(AppRoutes.ownerSettings),
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _TodayFigures(sales: sales),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Pending orders',
                    value: pending.when(
                      data: (count) => '$count',
                      loading: () => '—',
                      error: (error, stackTrace) => '—',
                    ),
                    icon: Icons.pending_actions_outlined,
                    onTap: () => context.go(AppRoutes.ownerOrders),
                    emphasis: (pending.valueOrNull ?? 0) > 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Low stock',
                    value: lowStock.when(
                      data: (products) => '${products.length}',
                      loading: () => '—',
                      error: (error, stackTrace) => '—',
                    ),
                    icon: Icons.inventory_outlined,
                    onTap: () => context.go(AppRoutes.ownerInventory),
                    emphasis: (lowStock.valueOrNull ?? const []).isNotEmpty,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Quick actions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            const _QuickActions(),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Running low',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(AppRoutes.ownerInventory),
                  child: const Text('Inventory'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _LowStockList(lowStock: lowStock),
          ],
        ),
      ),
    );
  }
}

class _TodayFigures extends StatelessWidget {
  const _TodayFigures({required this.sales});

  final AsyncValue<SalesSummary> sales;

  @override
  Widget build(BuildContext context) {
    return AsyncView<SalesSummary>(
      value: sales,
      compact: true,
      builder: (context, summary) {
        return Row(
          children: [
            Expanded(
              child: _StatCard(
                label: "Today's sales",
                value: summary.grossSales.format(),
                caption:
                    '${summary.orderCount} '
                    '${summary.orderCount == 1 ? 'order' : 'orders'}',
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: "Today's profit",
                value: summary.netProfit.format(),
                // Named honestly: this is revenue minus recorded cost plus the fees
                // collected. It is not a full P&L and should not read like one.
                caption: 'Goods margin + fees',
                icon: Icons.trending_up,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.onTap,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final VoidCallback? onTap;

  /// Draws attention when the number is something to act on.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: emphasis ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Scan restock', Icons.qr_code_scanner, AppRoutes.ownerScanRestock, true),
      ('Add product', Icons.add_box_outlined, AppRoutes.ownerProductNew, false),
      ('Inventory', Icons.inventory_outlined, AppRoutes.ownerInventory, false),
      ('Orders', Icons.receipt_long_outlined, AppRoutes.ownerOrders, false),
    ];

    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width < 400 ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        for (final (label, icon, route, isPrimary) in actions)
          _QuickAction(
            label: label,
            icon: icon,
            route: route,
            isPrimary: isPrimary,
          ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.route,
    required this.isPrimary,
  });

  final String label;
  final IconData icon;
  final String route;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = isPrimary
        ? theme.colorScheme.primary
        : theme.colorScheme.surface;
    final foreground = isPrimary
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => context.go(route),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: isPrimary
                  ? null
                  : Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 26),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LowStockList extends StatelessWidget {
  const _LowStockList({required this.lowStock});

  final AsyncValue<List<Product>> lowStock;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Product>>(
      value: lowStock,
      compact: true,
      builder: (context, products) {
        if (products.isEmpty) {
          return const EmptyView(
            compact: true,
            icon: Icons.check_circle_outline,
            title: 'Everything is stocked',
            message: 'No product has fallen to its low-stock level.',
          );
        }

        return Column(
          children: [
            for (final product in products.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StockBadge(
                          stockQuantity: product.stockQuantity,
                          lowStockThreshold: product.lowStockThreshold,
                        ),
                      ),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => context.go(AppRoutes.ownerScanRestock),
                      child: const Text('Restock'),
                    ),
                  ),
                ),
              ),
            if (products.length > 6)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.ownerInventory),
                  child: Text('${products.length - 6} more running low'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Formats a peso figure for a dashboard tile.
///
/// Exposed for the reports screens, which show the same figures over other periods.
String formatDashboardMoney(Money amount) => amount.format();
