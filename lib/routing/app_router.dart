import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/cart/presentation/cart_screen.dart';
import '../features/checkout/presentation/checkout_screen.dart';
import '../features/customer/presentation/customer_shell.dart';
import '../features/customer/presentation/home_screen.dart';
import '../features/customer/presentation/profile_screen.dart';
import '../features/orders/presentation/order_details_screen.dart';
import '../features/orders/presentation/order_history_screen.dart';
import '../features/owner/presentation/gcash_fee_settings_screen.dart';
import '../features/owner/presentation/inventory_history_screen.dart';
import '../features/owner/presentation/owner_dashboard_screen.dart';
import '../features/owner/presentation/owner_inventory_screen.dart';
import '../features/owner/presentation/owner_order_details_screen.dart';
import '../features/owner/presentation/owner_orders_screen.dart';
import '../features/owner/presentation/owner_products_screen.dart';
import '../features/owner/presentation/owner_sales_screen.dart';
import '../features/owner/presentation/owner_settings_screen.dart';
import '../features/owner/presentation/owner_shell.dart';
import '../features/owner/presentation/price_history_screen.dart';
import '../features/owner/presentation/pricing_settings_screen.dart';
import '../features/owner/presentation/product_form_screen.dart';
import '../features/owner/presentation/product_import_screen.dart';
import '../features/owner/presentation/scan_restock_screen.dart';
import '../features/products/presentation/categories_screen.dart';
import '../features/products/presentation/customer_scan_screen.dart';
import '../features/products/presentation/product_details_screen.dart';
import '../features/products/presentation/search_screen.dart';
import 'app_routes.dart';

/// Rebuilds the router's redirect whenever the signed-in session changes.
///
/// `go_router` needs a `Listenable`; Riverpod gives a stream. This adapter is the smallest
/// bridge between them, and it exists so the redirect below can be a pure function of the
/// current session rather than something that has to be manually re-run.
class _SessionRefreshNotifier extends ChangeNotifier {
  _SessionRefreshNotifier(this._ref) {
    _subscription = _ref.listen<AsyncValue<AuthSession?>>(
      authSessionProvider,
      (previous, next) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthSession?>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

final _routerRefreshProvider = Provider<_SessionRefreshNotifier>((ref) {
  final notifier = _SessionRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// The app's route table.
///
/// Two rules are enforced here, and both are about *navigation*, not security:
///
/// * Nothing but the splash renders until a session exists, so no screen has to handle a
///   null user.
/// * An owner lands in the owner shell and a shopper in the customer shell.
///
/// Neither of these protects owner data. A customer who types `/owner` is redirected, but
/// what actually stops them reading cost prices is the Firestore rules, which check the
/// `role` custom claim on every read. Client-side routing is a convenience for the person
/// holding the phone; it is not a boundary.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final session = ref.read(authSessionProvider);
      final location = state.matchedLocation;

      // Still working out who this is: hold on the splash.
      if (session.isLoading || !session.hasValue) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final current = session.valueOrNull;
      if (current == null) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final isOwner = current.isOwner;

      // A session exists, so the splash has done its job.
      if (location == AppRoutes.splash) {
        return isOwner ? AppRoutes.ownerDashboard : AppRoutes.home;
      }

      if (isOwner && !AppRoutes.isOwnerRoute(location)) {
        // The owner may still use the shopper screens deliberately; only bounce them off
        // the entry screens, which are meaningless once signed in.
        if (location == AppRoutes.welcome ||
            location == AppRoutes.login ||
            location == AppRoutes.register) {
          return AppRoutes.ownerDashboard;
        }
        return null;
      }

      if (!isOwner && AppRoutes.isOwnerRoute(location)) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) =>
            RegisterScreen(reason: state.uri.queryParameters['reason']),
      ),

      // ---------------------------------------------------------- customer
      //
      // Inside the shell: the five bottom-bar destinations, which keep the bar visible.
      ShellRoute(
        builder: (context, state, child) => CustomerShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.search,
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: AppRoutes.cart,
            builder: (context, state) => const CartScreen(),
          ),
          GoRoute(
            path: AppRoutes.orders,
            builder: (context, state) => const OrderHistoryScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Outside the shell: full-screen customer flows. A product page or a checkout
      // should own the whole screen rather than leaving a navigation bar to tap away from
      // a half-finished order.
      GoRoute(
        path: AppRoutes.categories,
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: AppRoutes.productDetails,
        builder: (context, state) =>
            ProductDetailsScreen(productId: state.pathParameters['productId']!),
      ),
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderConfirmation,
        builder: (context, state) => OrderDetailsScreen(
          orderId: state.pathParameters['orderId']!,
          isConfirmation: true,
        ),
      ),
      GoRoute(
        path: AppRoutes.orderDetails,
        builder: (context, state) =>
            OrderDetailsScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: AppRoutes.customerScan,
        builder: (context, state) => const CustomerScanScreen(),
      ),

      // ------------------------------------------------------------- owner
      //
      // Inside the shell: the four rail destinations.
      ShellRoute(
        builder: (context, state, child) => OwnerShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.ownerDashboard,
            builder: (context, state) => const OwnerDashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.ownerProducts,
            builder: (context, state) => const OwnerProductsScreen(),
          ),
          GoRoute(
            path: AppRoutes.ownerOrders,
            builder: (context, state) => const OwnerOrdersScreen(),
          ),
          GoRoute(
            path: AppRoutes.ownerSales,
            builder: (context, state) => const OwnerSalesScreen(),
          ),
        ],
      ),

      // Outside the shell: focused owner tasks. A restock run or a product form should
      // own the screen — a navigation bar under a live viewfinder is an invitation to
      // lose half a delivery.
      GoRoute(
        path: AppRoutes.ownerProductNew,
        builder: (context, state) {
          final arguments = state.extra;
          return ProductFormScreen(
            prefillBarcode: arguments is ProductFormArguments
                ? arguments.barcode
                : null,
            imported: arguments is ProductFormArguments
                ? arguments.imported
                : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.ownerProductImport,
        builder: (context, state) => const ProductImportScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerProductEdit,
        builder: (context, state) =>
            ProductFormScreen(productId: state.pathParameters['productId']),
      ),
      GoRoute(
        path: AppRoutes.ownerPriceHistory,
        builder: (context, state) =>
            PriceHistoryScreen(productId: state.pathParameters['productId']),
      ),
      GoRoute(
        path: AppRoutes.ownerStorePriceHistory,
        builder: (context, state) => const PriceHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerScanRestock,
        builder: (context, state) => const ScanRestockScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerInventory,
        builder: (context, state) => const OwnerInventoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerInventoryHistory,
        builder: (context, state) => const InventoryHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerOrderDetails,
        builder: (context, state) =>
            OwnerOrderDetailsScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: AppRoutes.ownerReports,
        builder: (context, state) => const OwnerSalesScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerPricingSettings,
        builder: (context, state) => const PricingSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerGcashFees,
        builder: (context, state) => const GcashFeeSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.ownerSettings,
        builder: (context, state) => const OwnerSettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        _RouteNotFoundScreen(location: state.uri.toString()),
  );
});

class _RouteNotFoundScreen extends ConsumerWidget {
  const _RouteNotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isOwnerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'We could not find that page.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                location,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(
                  isOwner ? AppRoutes.ownerDashboard : AppRoutes.home,
                ),
                child: Text(isOwner ? 'Go to dashboard' : 'Go to the store'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
