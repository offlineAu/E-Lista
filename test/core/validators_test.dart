import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/core/utils/validators.dart';
import 'package:e_lista/services/barcode_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money input', () {
    test('accepts what an owner types', () {
      expect(Validators.money('15'), isNull);
      expect(Validators.money('15.50'), isNull);
      expect(Validators.money('₱1,234.50'), isNull);
      expect(Validators.money('0'), isNull);
    });

    test('rejects nonsense and negatives', () {
      expect(Validators.money(''), isNotNull);
      expect(Validators.money('abc'), isNotNull);
      expect(Validators.money('-5'), contains('negative'));
      expect(Validators.money('15.999'), isNotNull);
    });

    test('zero can be disallowed where it would be a mistake', () {
      expect(Validators.money('0', allowZero: false), contains('more than'));
    });

    test('an amount over the ceiling is refused', () {
      expect(
        Validators.money('500', maximum: const Money.fromPesos(100)),
        contains('cannot be more than'),
      );
    });
  });

  group('profit percentage', () {
    test('accepts whole and fractional percentages', () {
      expect(Validators.profitPercentage('20'), isNull);
      expect(Validators.profitPercentage('20.5'), isNull);
      expect(Validators.profitPercentage('0'), isNull);
    });

    test('refuses a percentage at or above the ceiling', () {
      // The GCash formula divides by what is left of the margin, so 100% has no price.
      expect(Validators.profitPercentage('90'), isNotNull);
      expect(Validators.profitPercentage('100'), isNotNull);
      expect(Validators.profitPercentage('150'), isNotNull);
    });

    test('refuses a negative percentage', () {
      expect(Validators.profitPercentage('-5'), contains('negative'));
    });

    test('refuses malformed input', () {
      expect(Validators.profitPercentage(''), isNotNull);
      expect(Validators.profitPercentage('twenty'), isNotNull);
    });
  });

  group('quantities', () {
    test('stock must be a whole, non-negative number', () {
      expect(Validators.stockQuantity('0'), isNull);
      expect(Validators.stockQuantity('24'), isNull);
      expect(Validators.stockQuantity('-1'), contains('negative'));
      expect(Validators.stockQuantity('2.5'), isNotNull);
      expect(Validators.stockQuantity(''), isNotNull);
    });

    test('a movement of zero is not a movement', () {
      expect(Validators.movementQuantity('0'), contains('other than zero'));
      expect(Validators.movementQuantity('5'), isNull);
    });

    test('an order quantity is capped at the stock on hand', () {
      expect(Validators.orderQuantity('3', availableStock: 5), isNull);
      expect(
        Validators.orderQuantity('9', availableStock: 5),
        contains('Only 5 left'),
      );
      expect(
        Validators.orderQuantity('1', availableStock: 0),
        contains('out of stock'),
      );
      expect(Validators.orderQuantity('0', availableStock: 5), isNotNull);
    });
  });

  group('barcodes', () {
    test('accepts real retail barcode lengths', () {
      expect(Validators.barcode('12345678'), isNull); // EAN-8
      expect(Validators.barcode('4800016641107'), isNull); // EAN-13
      expect(Validators.barcode('12345678901234'), isNull); // ITF-14
    });

    test('refuses anything that is not a retail barcode', () {
      expect(Validators.barcode('1234567'), isNotNull); // Too short
      expect(Validators.barcode('123456789012345'), isNotNull); // Too long
      expect(Validators.barcode('48000ABC41107'), contains('digits only'));
    });

    test('is optional unless the caller says otherwise', () {
      expect(Validators.barcode(''), isNull);
      expect(Validators.barcode('', isRequired: true), isNotNull);
    });
  });

  group('scanner normalisation', () {
    test('accepts a retail barcode', () {
      expect(normaliseBarcode('4800016641107'), '4800016641107');
      expect(normaliseBarcode('  12345678  '), '12345678');
    });

    test('rejects a QR code, a misread fragment and an empty scan', () {
      expect(normaliseBarcode('https://example.com/promo'), isNull);
      expect(normaliseBarcode('123'), isNull);
      expect(normaliseBarcode(''), isNull);
      expect(normaliseBarcode(null), isNull);
    });

    test('the fake scanner hands out its script in order', () {
      final scanner = FakeBarcodeScannerService(
        scripted: ['4800016641107', '4801981132096'],
      );

      expect(scanner.nextScan(), '4800016641107');
      expect(scanner.nextScan(), '4801981132096');
      expect(scanner.nextScan(), isNull);
    });
  });

  group('contact details', () {
    test('accepts the phone formats people actually type', () {
      expect(Validators.phoneNumber('09171234567'), isNull);
      expect(Validators.phoneNumber('+639171234567'), isNull);
      expect(Validators.phoneNumber('(02) 8123 4567'), isNull);
    });

    test('refuses something too short to be a number', () {
      expect(Validators.phoneNumber('12345'), contains('too short'));
    });

    test('is optional where a store does not need it', () {
      expect(Validators.phoneNumber('', isRequired: false), isNull);
      expect(Validators.phoneNumber(''), isNotNull);
    });

    test('an email must look like one', () {
      expect(Validators.email('ana@example.com'), isNull);
      expect(Validators.email('ana@example'), isNotNull);
      expect(Validators.email('not an email'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('a password must be long enough to be worth having', () {
      expect(Validators.password('12345678'), isNull);
      expect(Validators.password('short'), contains('8 characters'));
      expect(Validators.password(''), isNotNull);
    });

    test('confirmation must match', () {
      expect(Validators.confirmPassword('abc12345', 'abc12345'), isNull);
      expect(Validators.confirmPassword('abc12345', 'different'), isNotNull);
    });
  });

  group('product fields', () {
    test('a name is required and bounded', () {
      expect(Validators.productName('Piattos'), isNull);
      expect(Validators.productName(''), isNotNull);
      expect(Validators.productName('x'), contains('too short'));
      expect(Validators.productName('x' * 200), isNotNull);
    });

    test('a unit is required and short', () {
      expect(Validators.unit('pc'), isNull);
      expect(Validators.unit(''), isNotNull);
      expect(Validators.unit('a very long unit description'), isNotNull);
    });
  });
}
