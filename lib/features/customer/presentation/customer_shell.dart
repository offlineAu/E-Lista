import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../widgets/floating_nav_bar.dart';
import '../../cart/application/cart_controller.dart';

/// The frame around every customer screen: bottom navigation and the cart badge.
///
/// Five destinations, all reachable in one tap, sized for a thumb. The cart carries a live
/// count because "did that go in?" is the question a shopper asks most.
class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.child, super.key});

  final Widget child;

  static const List<_Destination> _destinations = [
    _Destination(
      route: AppRoutes.home,
      label: 'Shop',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront,
    ),
    _Destination(
      route: AppRoutes.search,
      label: 'Search',
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
    ),
    _Destination(
      route: AppRoutes.cart,
      label: 'Cart',
      icon: Icons.shopping_cart_outlined,
      selectedIcon: Icons.shopping_cart,
      showsCartCount: true,
    ),
    _Destination(
      route: AppRoutes.orders,
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    _Destination(
      route: AppRoutes.profile,
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final cartCount = ref.watch(cartItemCountProvider);
    final selectedIndex = _indexFor(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          final destination = _destinations[index];
          if (destination.route == location) return;
          context.go(destination.route);
        },
        items: [
          for (final destination in _destinations)
            FloatingNavItem(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: destination.label,
              badgeCount: destination.showsCartCount ? cartCount : 0,
            ),
        ],
      ),
    );
  }

  /// Which tab a location belongs to.
  ///
  /// Sub-routes count as their parent tab — a product page keeps Shop highlighted — so the
  /// bar never appears to lose its place.
  static int _indexFor(String location) {
    for (var index = _destinations.length - 1; index >= 0; index--) {
      if (location.startsWith(_destinations[index].route)) return index;
    }
    return 0;
  }
}

class _Destination {
  const _Destination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.showsCartCount = false,
  });

  final String route;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool showsCartCount;
}
