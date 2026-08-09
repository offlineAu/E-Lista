import 'package:e_lista/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money construction', () {
    test('pesos convert to centavos', () {
      expect(const Money.fromPesos(18).centavos, 1800);
      expect(Money.zero.centavos, 0);
    });

    test('addition, subtraction and repetition are exact', () {
      const a = Money.fromCentavos(1875);
      const b = Money.fromCentavos(2500);

      expect((a + b).centavos, 4375);
      expect((b - a).centavos, 625);
      expect((a * 2).centavos, 3750);
      expect((-a).centavos, -1875);
    });

    test('summing many centavo amounts does not drift', () {
      // The classic binary floating point failure: 0.1 + 0.2 != 0.3. Repeating a centavo
      // amount a thousand times has to land on exactly ten pesos.
      final amounts = List.filled(1000, const Money.fromCentavos(1));
      expect(Money.sum(amounts), const Money.fromPesos(10));
    });

    test('sum of nothing is zero', () {
      expect(Money.sum(const []), Money.zero);
    });
  });

  group('Money.tryParse', () {
    test('accepts the shapes an owner actually types', () {
      expect(Money.tryParse('18'), const Money.fromPesos(18));
      expect(Money.tryParse('18.5'), const Money.fromCentavos(1850));
      expect(Money.tryParse('18.75'), const Money.fromCentavos(1875));
      expect(Money.tryParse('₱18.75'), const Money.fromCentavos(1875));
      expect(Money.tryParse(' 1,234.50 '), const Money.fromCentavos(123450));
      expect(Money.tryParse('-5.25'), const Money.fromCentavos(-525));
    });

    test('rejects malformed input instead of guessing', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('18.756'), isNull, reason: 'sub-centavo precision');
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('18-'), isNull);
    });
  });

  group('Money.floorToPeso', () {
    test('always rounds down, never to nearest', () {
      expect(
        const Money.fromCentavos(2099).floorToPeso(),
        const Money.fromPesos(20),
      );
      expect(
        const Money.fromCentavos(2050).floorToPeso(),
        const Money.fromPesos(20),
      );
      expect(
        const Money.fromCentavos(2001).floorToPeso(),
        const Money.fromPesos(20),
      );
      expect(
        const Money.fromCentavos(2000).floorToPeso(),
        const Money.fromPesos(20),
      );
    });

    test('rounds towards negative infinity for negative amounts', () {
      expect(
        const Money.fromCentavos(-2001).floorToPeso(),
        const Money.fromPesos(-21),
      );
    });
  });

  group('Money.format', () {
    test('drops centavos only when there are none', () {
      expect(const Money.fromCentavos(1800).format(), '₱18');
      expect(const Money.fromCentavos(1875).format(), '₱18.75');
      expect(const Money.fromCentavos(1805).format(), '₱18.05');
      expect(const Money.fromCentavos(50).format(), '₱0.50');
      expect(Money.zero.format(), '₱0');
    });

    test('formatExact keeps two decimals for aligned columns', () {
      expect(const Money.fromCentavos(1800).formatExact(), '₱18.00');
      expect(const Money.fromCentavos(1875).formatExact(), '₱18.75');
    });

    test('groups thousands and marks negatives', () {
      expect(const Money.fromCentavos(123450).format(), '₱1,234.50');
      expect(const Money.fromCentavos(100000000).format(), '₱1,000,000');
      expect(const Money.fromCentavos(-525).format(), '-₱5.25');
    });

    test('never shows a floating point artifact', () {
      // 18.75 is exactly representable here by construction; the point of the type is
      // that no code path can produce "18.749999999".
      for (var centavos = 0; centavos < 10000; centavos++) {
        final text = Money.fromCentavos(centavos).format();
        expect(text.split('.').length, lessThanOrEqualTo(2));
        final decimals = text.contains('.') ? text.split('.').last.length : 0;
        expect(decimals, lessThanOrEqualTo(2));
      }
    });
  });

  group('Money serialisation', () {
    test('round-trips through Firestore as an integer', () {
      const original = Money.fromCentavos(1875);
      expect(Money.fromJson(original.toJson()), original);
    });

    test('tolerates a double or string written by hand', () {
      expect(Money.fromJson(1875.0), const Money.fromCentavos(1875));
      expect(Money.fromJson(1874.6), const Money.fromCentavos(1875));
      expect(Money.fromJson('18.75'), const Money.fromCentavos(1875));
      expect(Money.fromJson(null), Money.zero);
    });

    test('rejects a value it cannot read', () {
      expect(
        () => Money.fromJson(<String>['nope']),
        throwsA(isA<MoneyException>()),
      );
    });
  });

  group('Money comparison', () {
    test('orders by centavos', () {
      const small = Money.fromCentavos(100);
      const large = Money.fromCentavos(200);

      expect(small < large, isTrue);
      expect(large > small, isTrue);
      expect(small <= const Money.fromCentavos(100), isTrue);
      expect(small >= const Money.fromCentavos(100), isTrue);
      expect(<Money>[large, small]..sort(), [small, large]);
    });

    test('equal amounts are equal and hash alike', () {
      expect(const Money.fromCentavos(1875), const Money.fromCentavos(1875));
      expect(
        const Money.fromCentavos(1875).hashCode,
        const Money.fromCentavos(1875).hashCode,
      );
    });
  });

  group('divideRoundHalfUp', () {
    test('rounds halves away from zero', () {
      expect(divideRoundHalfUp(5, 2), 3);
      expect(divideRoundHalfUp(-5, 2), -3);
      expect(divideRoundHalfUp(4, 2), 2);
      expect(divideRoundHalfUp(1, 3), 0);
      expect(divideRoundHalfUp(2, 3), 1);
    });

    test('refuses division by zero', () {
      expect(() => divideRoundHalfUp(1, 0), throwsA(isA<MoneyException>()));
    });
  });
}
