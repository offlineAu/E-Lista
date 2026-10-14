import 'package:e_lista/core/money/percentage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('construction', () {
    test('whole percents convert to basis points', () {
      expect(const Percentage.fromPercent(20).basisPoints, 2000);
      expect(const Percentage.fromPercent(100).basisPoints, 10000);
      expect(Percentage.zero.basisPoints, 0);
    });

    test('isAtLeastWhole marks a markup of 100% or more', () {
      expect(const Percentage.fromPercent(99).isAtLeastWhole, isFalse);
      expect(const Percentage.fromBasisPoints(9999).isAtLeastWhole, isFalse);
      expect(const Percentage.fromPercent(100).isAtLeastWhole, isTrue);
      expect(const Percentage.fromPercent(150).isAtLeastWhole, isTrue);
    });
  });

  group('tryParse', () {
    test('accepts what an owner types into the profit field', () {
      expect(Percentage.tryParse('20'), const Percentage.fromPercent(20));
      expect(Percentage.tryParse('20%'), const Percentage.fromPercent(20));
      expect(
        Percentage.tryParse(' 20.5 '),
        const Percentage.fromBasisPoints(2050),
      );
      expect(
        Percentage.tryParse('20.50'),
        const Percentage.fromBasisPoints(2050),
      );
      expect(
        Percentage.tryParse('20.05'),
        const Percentage.fromBasisPoints(2005),
      );
      expect(Percentage.tryParse('-5'), const Percentage.fromBasisPoints(-500));
    });

    test('rejects malformed input', () {
      expect(Percentage.tryParse(''), isNull);
      expect(Percentage.tryParse('abc'), isNull);
      expect(
        Percentage.tryParse('20.555'),
        isNull,
        reason: 'below one basis point',
      );
      expect(Percentage.tryParse('%'), isNull);
    });

    test('20.5% is exact — the reason percentages are not doubles', () {
      final parsed = Percentage.tryParse('20.5')!;
      expect(parsed.basisPoints, 2050);
      expect(parsed.format(), '20.5%');
    });
  });

  group('format', () {
    test('shows only the decimals that matter', () {
      expect(const Percentage.fromPercent(20).format(), '20%');
      expect(const Percentage.fromBasisPoints(2050).format(), '20.5%');
      expect(const Percentage.fromBasisPoints(2005).format(), '20.05%');
      expect(const Percentage.fromBasisPoints(-500).format(), '-5%');
      expect(Percentage.zero.format(), '0%');
    });
  });

  group('serialisation', () {
    test('round-trips through Firestore as basis points', () {
      const original = Percentage.fromBasisPoints(2050);
      expect(Percentage.fromJson(original.toJson()), original);
    });

    test('tolerates a double or string written by hand', () {
      expect(Percentage.fromJson(2000.0), const Percentage.fromPercent(20));
      expect(
        Percentage.fromJson('20.5'),
        const Percentage.fromBasisPoints(2050),
      );
      expect(Percentage.fromJson(null), Percentage.zero);
    });

    test('rejects a value it cannot read', () {
      expect(
        () => Percentage.fromJson(<String>['nope']),
        throwsA(isA<PercentageException>()),
      );
    });
  });

  test('orders and compares by basis points', () {
    expect(
      const Percentage.fromPercent(
        15,
      ).compareTo(const Percentage.fromPercent(20)),
      lessThan(0),
    );
    expect(
      const Percentage.fromPercent(20),
      const Percentage.fromBasisPoints(2000),
    );
    expect(
      const Percentage.fromPercent(20).hashCode,
      const Percentage.fromBasisPoints(2000).hashCode,
    );
  });
}
