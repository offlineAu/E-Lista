/// Every route path and name in one place.
///
/// Paths are written as constants rather than inline strings so a rename is a compile
/// error instead of a screen that silently stops being reachable.
abstract final class AppRoutes {
  // ------------------------------------------------------------------ entry
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';

  // --------------------------------------------------------------- customer
  static const String home = '/home';
  static const String search = '/search';
  static const String categories = '/categories';
  static const String cart = '/cart';
  static const String orders = '/orders';
  static const String profile = '/profile';

  static const String productDetails = '/product/:productId';
  static const String checkout = '/checkout';
  static const String orderConfirmation = '/order-confirmation/:orderId';
  static const String orderDetails = '/orders/:orderId';
  static const String customerScan = '/scan';
  static const String settings = '/settings';

  // ------------------------------------------------------------------ owner
  static const String ownerDashboard = '/owner';
  static const String ownerProducts = '/owner/products';
  static const String ownerProductNew = '/owner/products/new';
  static const String ownerProductEdit = '/owner/products/:productId/edit';
  static const String ownerProductImport = '/owner/products/import';
  static const String ownerPriceHistory =
      '/owner/products/:productId/price-history';
  static const String ownerStorePriceHistory = '/owner/price-history';
  static const String ownerInventory = '/owner/inventory';
  static const String ownerInventoryHistory = '/owner/inventory/history';
  static const String ownerScanRestock = '/owner/scan-restock';
  static const String ownerOrders = '/owner/orders';
  static const String ownerOrderDetails = '/owner/orders/:orderId';
  static const String ownerSales = '/owner/sales';
  static const String ownerReports = '/owner/reports';
  static const String ownerPricingSettings = '/owner/settings/pricing';
  static const String ownerGcashFees = '/owner/settings/gcash-fees';
  static const String ownerSettings = '/owner/settings';

  // ------------------------------------------------------------- path helpers

  static String productDetailsFor(String productId) => '/product/$productId';

  static String orderConfirmationFor(String orderId) =>
      '/order-confirmation/$orderId';

  static String orderDetailsFor(String orderId) => '/orders/$orderId';

  static String ownerProductEditFor(String productId) =>
      '/owner/products/$productId/edit';

  static String ownerPriceHistoryFor(String productId) =>
      '/owner/products/$productId/price-history';

  static String ownerOrderDetailsFor(String orderId) =>
      '/owner/orders/$orderId';

  /// Routes reachable while the app is still deciding who is signed in.
  static const Set<String> preSessionRoutes = {splash};

  /// Routes a signed-in owner should not land on; they are for shoppers.
  static bool isCustomerOnly(String location) =>
      !location.startsWith('/owner') && !preSessionRoutes.contains(location);

  static bool isOwnerRoute(String location) => location.startsWith('/owner');
}
