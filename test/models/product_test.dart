import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/core/money/percentage.dart';
import 'package:e_lista/features/pricing/domain/pricing_engine.dart';
import 'package:e_lista/models/inventory_transaction.dart';
import 'package:e_lista/models/payment_method.dart';
import 'package:e_lista/models/product.dart';
import 'package:e_lista/models/sale.dart';
import 'package:flutter_test/flutter_test.dart';

Product product({int stock = 10, int threshold = 3, bool isActive = true}) {
  return Product(
    id: 'piattos',
    name: 'Piattos Cheese',
    cashPrice: const Money.fromCentavos(1800),
    gcashBasePrice: const Money.fromCentavos(1875),
    stockQuantity: stock,
    lowStockThreshold: threshold,
    unit: 'pc',
    isActive: isActive,
  );
}

void main() {
  group('availability', () {
    test('low stock is at or below the threshold, not just under it', () {
      expect(product(stock: 4, threshold: 3).isLowStock, isFalse);
      expect(product(stock: 3, threshold: 3).isLowStock, isTrue);
      expect(product(stock: 2, threshold: 3).isLowStock, isTrue);
    });

    test('a threshold of zero still flags a sold-out product', () {
      expect(product(stock: 0, threshold: 0).isLowStock, isTrue);
    });

    test('purchasable means active and in stock', () {
      expect(product().isPurchasable, isTrue);
      expect(product(stock: 0).isPurchasable, isFalse);
      expect(product(isActive: false).isPurchasable, isFalse);
    });

    test('the order cap never goes negative', () {
      expect(product(stock: -5).maximumOrderQuantity, 0);
      expect(product(stock: 7).maximumOrderQuantity, 7);
    });
  });

  group('search tokens', () {
    test('every prefix of every word is indexed, so "piat" finds Piattos', () {
      final tokens = Product.buildSearchTokens(
        name: 'Piattos Cheese',
        brand: 'Jack n Jill',
      );

      expect(tokens, contains('pi'));
      expect(tokens, contains('piat'));
      expect(tokens, contains('piattos'));
      expect(tokens, contains('cheese'));
      expect(tokens, contains('jack'));
    });

    test('accents fold, so "cafe" finds "Café"', () {
      final tokens = Product.buildSearchTokens(name: 'Café Puro');
      expect(tokens, contains('cafe'));
    });

    test('one-letter words are skipped — they would match everything', () {
      final tokens = Product.buildSearchTokens(name: 'A Big Snack');
      expect(tokens, isNot(contains('a')));
      expect(tokens, contains('big'));
    });

    test('the barcode and its last four digits are searchable', () {
      final tokens = Product.buildSearchTokens(
        name: 'Piattos',
        barcode: '4800016641107',
      );
      expect(tokens, contains('4800016641107'));
      expect(tokens, contains('1107'));
    });

    test('punctuation does not create junk tokens', () {
      final tokens = Product.buildSearchTokens(name: 'Coca-Cola (295mL)');
      expect(tokens, contains('coca'));
      expect(tokens, contains('cola'));
      expect(tokens.every((token) => !token.contains('(')), isTrue);
    });

    test('the list stays small enough to index', () {
      final tokens = Product.buildSearchTokens(
        name: 'Lucky Me Pancit Canton Original Instant Noodles',
        brand: 'Lucky Me',
        categoryName: 'Instant Noodles',
        barcode: '4801981132096',
      );
      expect(tokens.length, lessThan(200));
    });

    test('normalisation collapses whitespace and case', () {
      expect(
        Product.normaliseForSearch('  Piattos   CHEESE '),
        'piattos cheese',
      );
    });
  });

  group('serialisation', () {
    test('round-trips through Firestore', () {
      final original = product();
      final restored = Product.fromJson('piattos', {
        ...original.toJson(),
        // Server timestamps are sentinels on write; a read gives back real values.
        'createdAt': null,
        'updatedAt': null,
      });

      expect(restored.name, original.name);
      expect(restored.cashPrice, original.cashPrice);
      expect(restored.gcashBasePrice, original.gcashBasePrice);
      expect(restored.stockQuantity, original.stockQuantity);
    });

    test(
      'materialises isLowStock, because Firestore cannot compare two fields',
      () {
        expect(product(stock: 2, threshold: 3).toJson()['isLowStock'], isTrue);
        expect(product(stock: 9, threshold: 3).toJson()['isLowStock'], isFalse);
      },
    );

    test('a document missing fields reads with safe defaults, not a crash', () {
      final restored = Product.fromJson('x', const {});

      expect(restored.name, 'Unnamed product');
      expect(restored.cashPrice, Money.zero);
      expect(restored.stockQuantity, 0);
      expect(restored.isActive, isTrue);
    });

    test('the public document carries no cost price', () {
      // Cost lives in products/{id}/private/pricing so the rules can refuse it. If it
      // ever leaked into this map, every customer could read it.
      expect(product().toJson().keys, isNot(contains('costPriceCentavos')));
      expect(product().toJson().keys, isNot(contains('profitBasisPoints')));
      expect(product().toJson().keys, isNot(contains('pricingMode')));
    });
  });

  group('owner-side product', () {
    test('reports the profit on each payment method', () {
      final owner = OwnerProduct(
        product: product(),
        cost: const ProductCost(
          productId: 'piattos',
          costPrice: Money.fromCentavos(1500),
          pricingMode: PricingMode.standard,
        ),
      );

      expect(owner.cashProfitPerUnit, const Money.fromCentavos(300));
      expect(owner.gcashProfitPerUnit, const Money.fromCentavos(375));
      expect(owner.inventoryValueAtCost, const Money.fromCentavos(15000));
    });

    test('a standard product follows the store default', () {
      const cost = ProductCost(
        productId: 'piattos',
        costPrice: Money.fromCentavos(1500),
        pricingMode: PricingMode.standard,
        profitPercentage: Percentage.fromPercent(50),
      );

      final prices = cost.pricesGiven(const Percentage.fromPercent(20));
      expect(prices.cash, const Money.fromPesos(18));
    });

    test('a custom product ignores the store default', () {
      const cost = ProductCost(
        productId: 'coke',
        costPrice: Money.fromCentavos(2000),
        pricingMode: PricingMode.custom,
        profitPercentage: Percentage.fromPercent(15),
      );

      expect(
        cost.pricesGiven(const Percentage.fromPercent(20)).cash,
        const Money.fromPesos(23),
      );
      expect(
        cost.pricesGiven(const Percentage.fromPercent(40)).cash,
        const Money.fromPesos(23),
        reason: 'raising the store default must not move a custom product',
      );
    });
  });

  group('inventory transactions', () {
    test('the balances agree with the change', () {
      const transaction = InventoryTransaction(
        id: 't1',
        productId: 'piattos',
        productName: 'Piattos',
        type: InventoryTransactionType.restock,
        quantity: 24,
        previousStock: 6,
        newStock: 30,
        referenceType: InventoryReferenceType.manual,
      );

      expect(transaction.isConsistent, isTrue);
      expect(transaction.isIncrease, isTrue);
      expect(transaction.signedQuantityLabel, '+24');
    });

    test('a row that does not add up is detectable', () {
      const broken = InventoryTransaction(
        id: 't1',
        productId: 'x',
        productName: 'x',
        type: InventoryTransactionType.sale,
        quantity: -3,
        previousStock: 10,
        newStock: 9,
        referenceType: InventoryReferenceType.order,
      );

      expect(broken.isConsistent, isFalse);
    });

    test('sales are recorded as a decrease', () {
      const sale = InventoryTransaction(
        id: 't1',
        productId: 'x',
        productName: 'x',
        type: InventoryTransactionType.sale,
        quantity: -3,
        previousStock: 10,
        newStock: 7,
        referenceType: InventoryReferenceType.order,
      );

      expect(sale.isIncrease, isFalse);
      expect(sale.signedQuantityLabel, '-3');
    });

    test('only some movement types need a reason', () {
      expect(InventoryTransactionType.adjustment.requiresReason, isTrue);
      expect(InventoryTransactionType.damage.requiresReason, isTrue);
      expect(InventoryTransactionType.expired.requiresReason, isTrue);
      expect(InventoryTransactionType.restock.requiresReason, isFalse);
    });

    test('only a restock may carry a new cost', () {
      expect(InventoryTransactionType.restock.acceptsCostUpdate, isTrue);
      for (final type in InventoryTransactionType.values.where(
        (t) => t != InventoryTransactionType.restock,
      )) {
        expect(type.acceptsCostUpdate, isFalse, reason: type.name);
      }
    });

    test('sales are not offered as a manual movement', () {
      expect(
        InventoryTransactionType.manuallyRecordable,
        isNot(contains(InventoryTransactionType.sale)),
      );
    });
  });

  group('sales and summaries', () {
    Sale sale({
      int gross = 6250,
      int cost = 5000,
      int fee = 50,
      PaymentMethod method = PaymentMethod.gcash,
    }) {
      return Sale(
        orderId: 'o1',
        paymentMethod: method,
        grossSales: Money.fromCentavos(gross),
        productCost: Money.fromCentavos(cost),
        convenienceFee: Money.fromCentavos(fee),
        itemCount: 3,
        completedAt: DateTime(2026, 8, 9, 14, 30),
      );
    }

    test('gross profit is revenue minus cost', () {
      expect(sale().grossProfit, const Money.fromCentavos(1250));
    });

    test('net profit counts the convenience fee as income', () {
      expect(sale().netProfit, const Money.fromCentavos(1300));
    });

    test('a cash sale has no fee to add', () {
      final cash = sale(fee: 0, method: PaymentMethod.cash);
      expect(cash.netProfit, cash.grossProfit);
    });

    test('margin is reported in exact basis points', () {
      // ₱12.50 profit on ₱62.50 of sales is exactly 20%.
      expect(sale().grossMarginBasisPoints, 2000);
    });

    test(
      'a zero-revenue sale has no margin rather than a division by zero',
      () {
        expect(sale(gross: 0, cost: 0).grossMarginBasisPoints, isNull);
      },
    );

    test('a summary adds up its sales and splits them by method', () {
      final summary = SalesSummary.summarise([
        sale(),
        sale(gross: 3000, cost: 2000, fee: 0, method: PaymentMethod.cash),
      ]);

      expect(summary.orderCount, 2);
      expect(summary.grossSales, const Money.fromCentavos(9250));
      expect(summary.productCost, const Money.fromCentavos(7000));
      expect(summary.grossProfit, const Money.fromCentavos(2250));
      expect(summary.convenienceFees, const Money.fromCentavos(50));
      expect(summary.netProfit, const Money.fromCentavos(2300));
      expect(summary.cashGrossSales, const Money.fromCentavos(3000));
      expect(summary.gcashGrossSales, const Money.fromCentavos(6250));
    });

    test('an empty period summarises to zero rather than to null', () {
      final summary = SalesSummary.summarise(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.grossSales, Money.zero);
      expect(summary.averageOrderValue, Money.zero);
    });

    test('the day key uses local time, because a store day is local', () {
      expect(Sale.dayKeyFor(DateTime(2026, 8, 9, 23, 59)), '2026-08-09');
      expect(Sale.dayKeyFor(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });
}
