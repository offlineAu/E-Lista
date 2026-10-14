import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/order.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/shimmer_loading.dart';
import '../../../widgets/state_views.dart';
import '../../orders/presentation/order_history_screen.dart';
import 'widgets/cashier_logout_action.dart';

/// Which orders the owner is looking at. `null` means every open one.
final ownerOrderFilterProvider = StateProvider<OrderStatus?>((ref) => null);

final ownerOrdersProvider = StreamProvider<List<StoreOrder>>((ref) {
  final filter = ref.watch(ownerOrderFilterProvider);
  final repository = ref.watch(orderRepositoryProvider);
  return filter == null
      ? repository.watchOpenOrders()
      : repository.watchByStatus(filter);
});

/// The order queue: what needs packing, in the order it arrived.
///
/// Open orders come oldest first on purpose. A queue sorted newest-first quietly starves
/// whoever ordered at nine in the morning.
class OwnerOrdersScreen extends ConsumerWidget {
  const OwnerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ownerOrdersProvider);
    final filter = ref.watch(ownerOrderFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: const [CashierLogoutAction()],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Open'),
                    selected: filter == null,
                    onSelected: (_) =>
                        ref.read(ownerOrderFilterProvider.notifier).state =
                            null,
                  ),
                ),
                for (final status in OrderStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(status.label),
                      selected: filter == status,
                      onSelected: (isSelected) =>
                          ref.read(ownerOrderFilterProvider.notifier).state =
                              isSelected ? status : null,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<StoreOrder>>(
              value: orders,
              onRetry: () => ref.invalidate(ownerOrdersProvider),
              loadingBuilder: (context) => const ShimmerListSkeleton(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
              ),
              builder: (context, list) {
                if (list.isEmpty) {
                  return EmptyView(
                    icon: Icons.receipt_long_outlined,
                    title: filter == null
                        ? 'No open orders'
                        : 'Nothing is ${filter.label.toLowerCase()}',
                    message: filter == null
                        ? 'Everything that came in has been dealt with.'
                        : 'Try another filter to see other orders.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) => OrderSummaryCard(
                    order: list[index],
                    showCustomer: true,
                    onTap: () => context.go(
                      AppRoutes.ownerOrderDetailsFor(list[index].id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
