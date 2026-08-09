import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';

/// The frame around the owner's screens.
///
/// Deliberately different from the customer shell: this is a back-office tool, so it uses
/// a rail on anything wider than a phone and a denser bottom bar on a phone. The owner is
/// working, often standing at the counter with one hand free, so the destinations are the
/// four things they do all day and everything else lives one level in.
class OwnerShell extends ConsumerWidget {
  const OwnerShell({required this.child, super.key});

  final Widget child;

  static const List<_OwnerDestination> _destinations = [
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFor(location);
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    void goTo(int index) {
      final destination = _destinations[index];
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
                for (final destination in _destinations)
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: goTo,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
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
  static int _indexFor(String location) {
    var bestIndex = 0;
    var bestLength = -1;
    for (var index = 0; index < _destinations.length; index++) {
      final route = _destinations[index].route;
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
