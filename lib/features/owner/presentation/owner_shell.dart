import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../widgets/floating_nav_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/register_view_providers.dart';

/// The frame around the owner's screens.
///
/// Deliberately different from the customer shell: this is a back-office tool, so it uses
/// a rail on anything wider than a phone and a denser bottom bar on a phone. The owner is
/// working, often standing at the counter with one hand free, so the destinations are the
/// four things they do all day and everything else lives one level in.
///
/// A cashier gets the same shell with a shorter destination list — Orders, Inventory and
/// New sale only, nothing that shows a margin or lets them change a price or manage staff.
/// An owner sees the same short list when [viewAsCashierProvider] is on, e.g. for working
/// the register themselves — a nav-layout preference, not a role change.
class OwnerShell extends ConsumerWidget {
  const OwnerShell({required this.child, super.key});

  final Widget child;

  static const List<_OwnerDestination> _fullDestinations = [
    _OwnerDestination(
      route: AppRoutes.ownerDashboard,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _OwnerDestination(
      route: AppRoutes.ownerProducts,
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
    _OwnerDestination(
      route: AppRoutes.ownerOrders,
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    _OwnerDestination(
      route: AppRoutes.ownerSales,
      label: 'Sales',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
  ];

  static const List<_OwnerDestination> _cashierDestinations = [
    _OwnerDestination(
      route: AppRoutes.ownerOrders,
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    _OwnerDestination(
      route: AppRoutes.ownerInventory,
      label: 'Inventory',
      icon: Icons.inventory_outlined,
      selectedIcon: Icons.inventory,
    ),
    _OwnerDestination(
      route: AppRoutes.ownerPosCheckout,
      label: 'New sale',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCashier = ref.watch(isCashierProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final viewAsCashier = ref.watch(viewAsCashierProvider);
    final destinations = (isCashier || (isOwner && viewAsCashier))
        ? _cashierDestinations
        : _fullDestinations;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFor(destinations, location);
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    void goTo(int index) {
      final destination = destinations[index];
      if (destination.route == location) return;
      context.go(destination.route);
    }

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: goTo,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: goTo,
        items: [
          for (final destination in destinations)
            FloatingNavItem(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: destination.label,
            ),
        ],
      ),
    );
  }

  /// Which destination owns a location.
  ///
  /// Longest match wins, so `/owner/products/new` highlights Products while `/owner`
  /// highlights Dashboard — a plain `startsWith` in declaration order would light up
  /// Dashboard for every owner screen, since every one of them starts with `/owner`.
  static int _indexFor(List<_OwnerDestination> destinations, String location) {
    var bestIndex = 0;
    var bestLength = -1;
    for (var index = 0; index < destinations.length; index++) {
      final route = destinations[index].route;
      if (location.startsWith(route) && route.length > bestLength) {
        bestIndex = index;
        bestLength = route.length;
      }
    }
    return bestIndex;
  }
}

class _OwnerDestination {
  const _OwnerDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String route;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
