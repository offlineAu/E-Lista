import 'package:e_lista/core/errors/app_failure.dart';
import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/core/theme/app_theme.dart';
import 'package:e_lista/models/product.dart';
import 'package:e_lista/widgets/price_display.dart';
import 'package:e_lista/widgets/product_card.dart';
import 'package:e_lista/widgets/quantity_stepper.dart';
import 'package:e_lista/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget in enough app to render: the real theme, so anything that depends on a
/// colour or a text style is exercised as it will be in the app.
Widget host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );
}

Product product({
  int cashCentavos = 1800,
  int gcashCentavos = 1875,
  int stock = 10,
  int threshold = 3,
  bool isActive = true,
}) {
  return Product(
    id: 'piattos',
    name: 'Piattos Cheese',
    brand: 'Jack n Jill',
    cashPrice: Money.fromCentavos(cashCentavos),
    gcashBasePrice: Money.fromCentavos(gcashCentavos),
    stockQuantity: stock,
    lowStockThreshold: threshold,
    unit: 'pc',
    isActive: isActive,
  );
}

void main() {
  group('DualPriceView', () {
    testWidgets('shows both prices, labelled', (tester) async {
      await tester.pumpWidget(
        host(
          const DualPriceView(
            cashPrice: Money.fromCentavos(1800),
            gcashPrice: Money.fromCentavos(1875),
          ),
        ),
      );

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      // Cash is whole pesos and reads as ₱18; GCash keeps its centavos.
      expect(find.text('₱18'), findsOneWidget);
      expect(find.text('₱18.75'), findsOneWidget);
    });

    testWidgets('never renders a floating point artifact', (tester) async {
      await tester.pumpWidget(
        host(
          const DualPriceView(
            cashPrice: Money.fromCentavos(1800),
            gcashPrice: Money.fromCentavos(1875),
          ),
        ),
      );

      expect(find.textContaining('999999'), findsNothing);
      expect(find.textContaining('18.7500'), findsNothing);
    });
  });

  group('StockBadge', () {
    testWidgets('says how much is left', (tester) async {
      await tester.pumpWidget(
        host(const StockBadge(stockQuantity: 12, lowStockThreshold: 3)),
      );
      expect(find.text('12 in stock'), findsOneWidget);
    });

    testWidgets('marks low stock in words, not only in colour', (tester) async {
      await tester.pumpWidget(
        host(const StockBadge(stockQuantity: 3, lowStockThreshold: 3)),
      );
      expect(find.textContaining('Low stock'), findsOneWidget);
    });

    testWidgets('marks out of stock in words', (tester) async {
      await tester.pumpWidget(
        host(const StockBadge(stockQuantity: 0, lowStockThreshold: 3)),
      );
      expect(find.text('Out of stock'), findsOneWidget);
    });

    testWidgets('carries an icon as well as colour', (tester) async {
      await tester.pumpWidget(
        host(const StockBadge(stockQuantity: 0, lowStockThreshold: 3)),
      );
      expect(find.byType(Icon), findsOneWidget);
    });
  });

  group('QuantityStepper', () {
    testWidgets('increments and decrements', (tester) async {
      var quantity = 2;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => QuantityStepper(
              quantity: quantity,
              maximum: 5,
              onChanged: (value) => setState(() => quantity = value),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(quantity, 3);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(quantity, 2);
    });

    testWidgets('will not go above the stock on hand', (tester) async {
      var quantity = 5;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => QuantityStepper(
              quantity: quantity,
              maximum: 5,
              onChanged: (value) => setState(() => quantity = value),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(quantity, 5, reason: 'the plus button is disabled at the cap');
    });

    testWidgets('will not go below the minimum', (tester) async {
      var quantity = 1;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => QuantityStepper(
              quantity: quantity,
              onChanged: (value) => setState(() => quantity = value),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(quantity, 1);
    });

    testWidgets('buttons meet the minimum touch target', (tester) async {
      await tester.pumpWidget(
        host(QuantityStepper(quantity: 1, maximum: 5, onChanged: (_) {})),
      );

      final size = tester.getSize(find.byIcon(Icons.add).first);
      expect(size.width, greaterThan(0));

      final buttonSize = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.add),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(buttonSize.height, greaterThanOrEqualTo(AppTheme.minTouchTarget));
    });
  });

  group('ProductCard', () {
    testWidgets('shows the name, brand and both prices', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(product: product(), onTap: () {}),
          ),
        ),
      );

      expect(find.text('Piattos Cheese'), findsOneWidget);
      expect(find.text('Jack n Jill'), findsOneWidget);
      expect(find.text('₱18'), findsOneWidget);
      expect(find.text('₱18.75'), findsOneWidget);
    });

    testWidgets('shows out of stock instead of the unit', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(product: product(stock: 0), onTap: () {}),
          ),
        ),
      );

      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('per pc'), findsNothing);
    });

    testWidgets('disables adding a sold-out product to the cart', (
      tester,
    ) async {
      var added = false;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(
              product: product(stock: 0),
              onTap: () {},
              onAddToCart: () => added = true,
            ),
          ),
        ),
      );

      await tester.tap(
        find.byIcon(Icons.add_shopping_cart),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(added, isFalse);
    });

    testWidgets('adds an in-stock product to the cart', (tester) async {
      var added = false;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(
              product: product(),
              onTap: () {},
              onAddToCart: () => added = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add_shopping_cart));
      await tester.pump();
      expect(added, isTrue);
    });

    testWidgets('shows what is already in the cart', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(
              product: product(),
              onTap: () {},
              quantityInCart: 2,
            ),
          ),
        ),
      );

      expect(find.text('2 in cart'), findsOneWidget);
    });

    testWidgets('is announced to a screen reader with its prices', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(product: product(), onTap: () {}),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Piattos Cheese.*Cash ₱18.*GCash ₱18.75')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('state views', () {
    testWidgets('the empty state says what to do next', (tester) async {
      await tester.pumpWidget(
        host(
          EmptyView(
            title: 'No products found',
            message: 'Try another name.',
            action: FilledButton(onPressed: () {}, child: const Text('Clear')),
          ),
        ),
      );

      expect(find.text('No products found'), findsOneWidget);
      expect(find.text('Try another name.'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('a retryable failure offers Try again', (tester) async {
      await tester.pumpWidget(
        host(ErrorView(failure: const AppFailure.offline(), onRetry: () {})),
      );

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a permanent failure does not offer a pointless retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ErrorView(failure: const AppFailure.notAllowed(), onRetry: () {})),
      );

      expect(find.text('Try again'), findsNothing);
      expect(
        find.text('You do not have permission to do that.'),
        findsOneWidget,
      );
    });

    testWidgets('never shows a raw exception string', (tester) async {
      await tester.pumpWidget(
        host(
          ErrorView.from(
            Exception('FirebaseError 7: PERMISSION_DENIED'),
            StackTrace.current,
          ),
        ),
      );

      expect(find.textContaining('FirebaseError'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('the loading state can carry a message', (tester) async {
      await tester.pumpWidget(host(const LoadingView(message: 'Loading…')));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading…'), findsOneWidget);
    });
  });
}
