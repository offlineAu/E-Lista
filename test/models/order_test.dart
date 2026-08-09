import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/models/order.dart';
import 'package:e_lista/models/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

OrderItem item({
  String productId = 'piattos',
  int quantity = 2,
  int unitCentavos = 1875,
}) {
  return OrderItem(
    productId: productId,
    productName: 'Piattos Cheese',
    quantity: quantity,
    cashPriceAtPurchase: const Money.fromCentavos(1800),
    gcashPriceAtPurchase: Money.fromCentavos(unitCentavos),
    selectedUnitPrice: Money.fromCentavos(unitCentavos),
    lineTotal: Money.fromCentavos(unitCentavos * quantity),
  );
}

StoreOrder order({
  OrderStatus status = OrderStatus.pending,
  PaymentMethod paymentMethod = PaymentMethod.gcash,
  List<OrderItem>? items,
  int feeCentavos = 50,
}) {
  final lines = items ?? [item()];
  final subtotal = Money.sum(lines.map((line) => line.lineTotal));
  final fee = Money.fromCentavos(feeCentavos);

  return StoreOrder(
    id: 'order-1',
    customerId: 'uid-1',
    customerType: CustomerType.guest,
    paymentMethod: paymentMethod,
    status: status,
    items: lines,
    subtotal: subtotal,
    convenienceFee: fee,
    total: subtotal + fee,
    contact: const OrderContact(name: 'Ana', phoneNumber: '09171234567'),
  );
}

void main() {
  group('status workflow', () {
    test('follows the documented happy path', () {
      expect(OrderStatus.pending.canMoveTo(OrderStatus.confirmed), isTrue);
      expect(OrderStatus.confirmed.canMoveTo(OrderStatus.preparing), isTrue);
      expect(OrderStatus.preparing.canMoveTo(OrderStatus.ready), isTrue);
      expect(OrderStatus.ready.canMoveTo(OrderStatus.completed), isTrue);
    });

    test('cannot skip ahead', () {
      expect(OrderStatus.pending.canMoveTo(OrderStatus.completed), isFalse);
      expect(OrderStatus.pending.canMoveTo(OrderStatus.ready), isFalse);
      expect(OrderStatus.confirmed.canMoveTo(OrderStatus.completed), isFalse);
    });

    test('cannot go backwards', () {
      expect(OrderStatus.ready.canMoveTo(OrderStatus.preparing), isFalse);
      expect(OrderStatus.completed.canMoveTo(OrderStatus.ready), isFalse);
    });

    test('can be cancelled from any open state', () {
      for (final status in OrderStatus.values.where((s) => s.isOpen)) {
        expect(
          status.canMoveTo(OrderStatus.cancelled),
          isTrue,
          reason: status.name,
        );
      }
    });

    test('a finished order cannot change', () {
      expect(OrderStatus.completed.allowedNext, isEmpty);
      expect(OrderStatus.cancelled.allowedNext, isEmpty);
      expect(OrderStatus.completed.isFinal, isTrue);
      expect(OrderStatus.cancelled.isFinal, isTrue);
    });

    test('open orders hold reserved stock; finished ones do not', () {
      expect(OrderStatus.pending.holdsStock, isTrue);
      expect(OrderStatus.ready.holdsStock, isTrue);
      expect(OrderStatus.completed.holdsStock, isFalse);
      expect(OrderStatus.cancelled.holdsStock, isFalse);
    });

    test('the customer tracker covers every non-cancelled state', () {
      for (final status in OrderStatus.values) {
        if (status == OrderStatus.cancelled) {
          expect(status.trackingStep, isNull);
        } else {
          expect(status.trackingStep, isNotNull, reason: status.name);
          expect(status.trackingStep!, lessThan(OrderStatus.trackingStepCount));
        }
      }
    });

    test('an unknown stored status reads as pending rather than crashing', () {
      expect(OrderStatus.fromJson('nonsense'), OrderStatus.pending);
      expect(OrderStatus.fromJson(null), OrderStatus.pending);
    });
  });

  group('totals', () {
    test('the stored totals agree with the stored lines', () {
      expect(order().isConsistent, isTrue);
    });

    test('a tampered total is detected rather than trusted', () {
      final tampered = StoreOrder(
        id: 'order-1',
        customerId: 'uid-1',
        customerType: CustomerType.registered,
        paymentMethod: PaymentMethod.gcash,
        status: OrderStatus.pending,
        items: [item()],
        subtotal: const Money.fromCentavos(3750),
        convenienceFee: const Money.fromCentavos(50),
        total: const Money.fromCentavos(1), // Nonsense.
        contact: const OrderContact(name: 'Ana', phoneNumber: '0917'),
      );

      expect(tampered.isConsistent, isFalse);
    });

    test('a line total that does not match its parts is detected', () {
      const broken = OrderItem(
        productId: 'x',
        productName: 'x',
        quantity: 2,
        cashPriceAtPurchase: Money.fromCentavos(1000),
        gcashPriceAtPurchase: Money.fromCentavos(1000),
        selectedUnitPrice: Money.fromCentavos(1000),
        lineTotal: Money.fromCentavos(9999),
      );

      expect(broken.isConsistent, isFalse);
      expect(broken.recomputedLineTotal, const Money.fromCentavos(2000));
    });

    test('counts units, not lines', () {
      final twoLines = order(
        items: [
          item(quantity: 2),
          item(productId: 'coke', quantity: 3),
        ],
      );
      expect(twoLines.itemCount, 5);
      expect(twoLines.lineCount, 2);
    });
  });

  group('historical prices', () {
    test('an order keeps what the customer paid, whatever happens later', () {
      // Piattos was ₱18 when this order was placed.
      final placed = order(
        paymentMethod: PaymentMethod.cash,
        items: [
          const OrderItem(
            productId: 'piattos',
            productName: 'Piattos Cheese',
            quantity: 1,
            cashPriceAtPurchase: Money.fromCentavos(1800),
            gcashPriceAtPurchase: Money.fromCentavos(1875),
            selectedUnitPrice: Money.fromCentavos(1800),
            lineTotal: Money.fromCentavos(1800),
          ),
        ],
        feeCentavos: 0,
      );

      // The product is re-priced to ₱20 tomorrow. The order is a snapshot: there is no
      // reference to the product document to follow, so nothing about it can change.
      final restored = StoreOrder.fromJson('order-1', placed.toJson());

      expect(
        restored.items.single.selectedUnitPrice,
        const Money.fromCentavos(1800),
      );
      expect(restored.total, const Money.fromCentavos(1800));
    });

    test('both price lists are preserved, not just the one charged', () {
      final restored = StoreOrder.fromJson('order-1', order().toJson());
      final line = restored.items.single;

      expect(line.cashPriceAtPurchase, const Money.fromCentavos(1800));
      expect(line.gcashPriceAtPurchase, const Money.fromCentavos(1875));
      expect(line.selectedUnitPrice, line.gcashPriceAtPurchase);
    });

    test(
      'the product name is a snapshot, so a rename cannot blank out history',
      () {
        final restored = StoreOrder.fromJson('order-1', order().toJson());
        expect(restored.items.single.productName, 'Piattos Cheese');
      },
    );
  });

  group('cost snapshot', () {
    test('line costs multiply out and sum', () {
      const snapshot = OrderCostSnapshot(
        orderId: 'order-1',
        lines: [
          OrderCostLine(
            productId: 'piattos',
            quantity: 2,
            costPriceAtPurchase: Money.fromCentavos(1500),
          ),
          OrderCostLine(
            productId: 'coke',
            quantity: 1,
            costPriceAtPurchase: Money.fromCentavos(2000),
          ),
        ],
        totalProductCost: Money.fromCentavos(5000),
      );

      expect(snapshot.lines.first.lineCost, const Money.fromCentavos(3000));
      expect(
        Money.sum(snapshot.lines.map((line) => line.lineCost)),
        snapshot.totalProductCost,
      );
    });

    test('round-trips through Firestore', () {
      const snapshot = OrderCostSnapshot(
        orderId: 'order-1',
        lines: [
          OrderCostLine(
            productId: 'piattos',
            quantity: 2,
            costPriceAtPurchase: Money.fromCentavos(1500),
          ),
        ],
        totalProductCost: Money.fromCentavos(3000),
      );

      final restored = OrderCostSnapshot.fromJson('order-1', {
        'lines': snapshot.lines.map((line) => line.toJson()).toList(),
        'totalProductCostCentavos': 3000,
      });

      expect(restored.totalProductCost, const Money.fromCentavos(3000));
      expect(restored.lines.single.quantity, 2);
    });
  });

  group('payment methods', () {
    test('cash carries no convenience fee; GCash does', () {
      expect(PaymentMethod.cash.chargesConvenienceFee, isFalse);
      expect(PaymentMethod.gcash.chargesConvenienceFee, isTrue);
    });

    test('an unknown stored method reads as cash, inventing no fee', () {
      final method = PaymentMethod.fromJson('maya');
      expect(method, PaymentMethod.cash);
      expect(method.chargesConvenienceFee, isFalse);
    });

    test('ids are stable, because historical orders are read back by them', () {
      expect(PaymentMethod.cash.id, 'cash');
      expect(PaymentMethod.gcash.id, 'gcash');
    });
  });

  group('contact details', () {
    test('an address means delivery', () {
      const delivery = OrderContact(
        name: 'Ana',
        phoneNumber: '0917',
        address: '12 Mabini St',
      );
      expect(delivery.isDelivery, isTrue);
    });

    test('no address means pickup', () {
      const pickup = OrderContact(name: 'Ana', phoneNumber: '0917');
      expect(pickup.isDelivery, isFalse);
    });

    test('a blank address is not a delivery', () {
      const blank = OrderContact(
        name: 'Ana',
        phoneNumber: '0917',
        address: '   ',
      );
      expect(blank.isDelivery, isFalse);
    });
  });
}
