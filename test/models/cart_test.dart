import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/features/pricing/domain/gcash_fee_schedule.dart';
import 'package:e_lista/models/cart.dart';
import 'package:e_lista/models/payment_method.dart';
import 'package:e_lista/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

Product product({
  String id = 'piattos',
  String name = 'Piattos Cheese',
  int cashCentavos = 1800,
  int gcashCentavos = 1875,
  int stock = 10,
  bool isActive = true,
}) {
  return Product(
    id: id,
    name: name,
    cashPrice: Money.fromCentavos(cashCentavos),
    gcashBasePrice: Money.fromCentavos(gcashCentavos),
    stockQuantity: stock,
    lowStockThreshold: 3,
    unit: 'pc',
    isActive: isActive,
  );
}

void main() {
  final schedule = GcashFeeSchedule.defaultSchedule;

  group('adding products', () {
    test('adds a new line', () {
      final cart = Cart.empty.addProduct(product());

      expect(cart.lineCount, 1);
      expect(cart.itemCount, 1);
      expect(cart.quantityOf('piattos'), 1);
    });

    test('merges into the existing line instead of duplicating it', () {
      final cart = Cart.empty
          .addProduct(product(), quantity: 2)
          .addProduct(product(), quantity: 3);

      expect(cart.lineCount, 1);
      expect(cart.quantityOf('piattos'), 5);
    });

    test('never exceeds the stock last seen', () {
      final cart = Cart.empty.addProduct(product(stock: 4), quantity: 10);
      expect(cart.quantityOf('piattos'), 4);
    });

    test('merging is also capped at stock', () {
      final cart = Cart.empty
          .addProduct(product(stock: 4), quantity: 3)
          .addProduct(product(stock: 4), quantity: 3);
      expect(cart.quantityOf('piattos'), 4);
    });

    test('keeps separate lines for separate products', () {
      final cart = Cart.empty
          .addProduct(product())
          .addProduct(product(id: 'coke', name: 'Coke Sakto'));

      expect(cart.lineCount, 2);
      expect(cart.itemCount, 2);
    });
  });

  group('changing quantities', () {
    test('sets a quantity', () {
      final cart = Cart.empty
          .addProduct(product())
          .updateQuantity('piattos', 7);
      expect(cart.quantityOf('piattos'), 7);
    });

    test('a quantity of zero removes the line', () {
      final cart = Cart.empty
          .addProduct(product())
          .updateQuantity('piattos', 0);
      expect(cart.isEmpty, isTrue);
    });

    test('removing a product leaves the others alone', () {
      final cart = Cart.empty
          .addProduct(product())
          .addProduct(product(id: 'coke'))
          .removeProduct('piattos');

      expect(cart.lineCount, 1);
      expect(cart.findItem('coke'), isNotNull);
    });

    test('clear empties everything', () {
      expect(Cart.empty.addProduct(product()).clear().isEmpty, isTrue);
    });
  });

  group('totals', () {
    test('cash and GCash subtotals use their own price list', () {
      final cart = Cart.empty.addProduct(product(), quantity: 2);

      expect(cart.subtotal(PaymentMethod.cash), const Money.fromCentavos(3600));
      expect(
        cart.subtotal(PaymentMethod.gcash),
        const Money.fromCentavos(3750),
      );
    });

    test('cash orders never carry a convenience fee', () {
      final cart = Cart.empty.addProduct(product(), quantity: 2);
      expect(cart.convenienceFee(PaymentMethod.cash, schedule), Money.zero);
      expect(
        cart.total(PaymentMethod.cash, schedule),
        cart.subtotal(PaymentMethod.cash),
      );
    });

    test('the GCash fee is charged once, not per line', () {
      // Two lines of ₱18.75×2 and ₱25.00×1 — the worked example from the specification.
      final cart = Cart.empty
          .addProduct(product(gcashCentavos: 1875), quantity: 2)
          .addProduct(product(id: 'coke', gcashCentavos: 2500), quantity: 1);

      expect(
        cart.subtotal(PaymentMethod.gcash),
        const Money.fromCentavos(6250),
      );
      expect(
        cart.convenienceFee(PaymentMethod.gcash, schedule),
        const Money.fromCentavos(50),
      );
      expect(
        cart.total(PaymentMethod.gcash, schedule),
        const Money.fromCentavos(6300),
      );
    });

    test('adding a third line does not add a third fee', () {
      final twoLines = Cart.empty
          .addProduct(product(gcashCentavos: 1875))
          .addProduct(product(id: 'coke', gcashCentavos: 1875));
      final threeLines = twoLines.addProduct(
        product(id: 'nova', gcashCentavos: 1875),
      );

      expect(
        threeLines.convenienceFee(PaymentMethod.gcash, schedule),
        twoLines.convenienceFee(PaymentMethod.gcash, schedule),
      );
    });

    test('an empty cart totals zero', () {
      expect(Cart.empty.subtotal(PaymentMethod.cash), Money.zero);
      expect(Cart.empty.total(PaymentMethod.gcash, schedule), Money.zero);
    });
  });

  group('problems that block checkout', () {
    test('a fresh cart can check out', () {
      expect(Cart.empty.addProduct(product()).canCheckout, isTrue);
    });

    test('an empty cart cannot', () {
      expect(Cart.empty.canCheckout, isFalse);
    });

    test('a deactivated product blocks checkout and says why', () {
      final cart = Cart.empty.addProduct(product()).refreshedFrom({
        'piattos': product(isActive: false),
      });

      expect(cart.canCheckout, isFalse);
      expect(cart.problemItems.single.problemMessage, 'No longer available');
    });

    test('a sold-out product blocks checkout and says why', () {
      final cart = Cart.empty.addProduct(product()).refreshedFrom({
        'piattos': product(stock: 0),
      });

      expect(cart.canCheckout, isFalse);
      expect(cart.problemItems.single.problemMessage, 'Out of stock');
    });
  });

  group('refreshing from the catalog', () {
    test('picks up a new price', () {
      final cart = Cart.empty.addProduct(product());
      final refreshed = cart.refreshedFrom({
        'piattos': product(cashCentavos: 2000, gcashCentavos: 2085),
      });

      expect(
        refreshed.findItem('piattos')!.cashPrice,
        const Money.fromCentavos(2000),
      );
    });

    test('caps the quantity at what is actually left', () {
      final cart = Cart.empty.addProduct(product(), quantity: 8);
      final refreshed = cart.refreshedFrom({'piattos': product(stock: 3)});

      expect(refreshed.findItem('piattos')!.quantity, 3);
    });

    test('drops a product that no longer exists', () {
      final cart = Cart.empty
          .addProduct(product())
          .addProduct(product(id: 'coke'));
      final refreshed = cart.refreshedFrom({'coke': product(id: 'coke')});

      expect(refreshed.lineCount, 1);
      expect(refreshed.findItem('piattos'), isNull);
    });

    test(
      'keeps a sold-out line so the shopper is told rather than surprised',
      () {
        final cart = Cart.empty.addProduct(product());
        final refreshed = cart.refreshedFrom({'piattos': product(stock: 0)});

        expect(refreshed.lineCount, 1);
        expect(refreshed.findItem('piattos')!.hasProblem, isTrue);
      },
    );
  });

  group('serialisation', () {
    test('round-trips through Firestore', () {
      final cart = Cart.empty.addProduct(product(), quantity: 3);
      final json = cart.toJson();
      final items = (json['items']! as List).cast<Map<String, Object?>>();
      final restored = Cart.fromJson({'items': items});

      expect(restored.lineCount, 1);
      expect(restored.quantityOf('piattos'), 3);
      expect(
        restored.subtotal(PaymentMethod.gcash),
        cart.subtotal(PaymentMethod.gcash),
      );
    });

    test('a missing document reads as an empty cart', () {
      expect(Cart.fromJson(null).isEmpty, isTrue);
    });
  });
}
