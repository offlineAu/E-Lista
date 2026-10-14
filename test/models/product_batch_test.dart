import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/models/product_batch.dart';
import 'package:flutter_test/flutter_test.dart';

ProductBatch _batch({required int remainingQuantity, required Money unitCost}) {
  return ProductBatch(
    id: 'batch-1',
    productId: 'product-1',
    productName: 'Test product',
    initialQuantity: remainingQuantity,
    remainingQuantity: remainingQuantity,
    unitCost: unitCost,
    expiryDate: noExpirySentinel,
    hasExpiry: false,
  );
}

void main() {
  group('remaining value', () {
    test('is the unit cost times what is left, not what it started with', () {
      final batch = _batch(remainingQuantity: 4, unitCost: Money.fromPesos(15));
      expect(batch.remainingValue, Money.fromPesos(60));
    });

    test('is zero once a batch is depleted', () {
      final batch = _batch(remainingQuantity: 0, unitCost: Money.fromPesos(15));
      expect(batch.remainingValue, Money.zero);
    });
  });

  group('expiringSoonValue', () {
    test('sums the remaining value across every batch given', () {
      final batches = [
        _batch(remainingQuantity: 2, unitCost: Money.fromPesos(10)),
        _batch(remainingQuantity: 3, unitCost: Money.fromPesos(20)),
      ];
      expect(expiringSoonValue(batches), Money.fromPesos(80));
    });

    test('is zero for an empty list rather than throwing', () {
      expect(expiringSoonValue(const []), Money.zero);
    });
  });
}
