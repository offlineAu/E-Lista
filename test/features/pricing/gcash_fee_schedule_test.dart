import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/features/pricing/domain/gcash_fee_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

GcashFeeTier tier(int minCentavos, int? maxCentavos, int feeCentavos) {
  return GcashFeeTier(
    min: Money.fromCentavos(minCentavos),
    max: maxCentavos == null ? null : Money.fromCentavos(maxCentavos),
    fee: Money.fromCentavos(feeCentavos),
  );
}

void main() {
  final schedule = GcashFeeSchedule.defaultSchedule;

  group('tier boundaries', () {
    test('every documented boundary resolves to the tier it belongs to', () {
      // The centavo either side of each boundary is what breaks in a naive
      // implementation, so both sides of each are pinned.
      final expectations = <int, int>{
        0: 50, // ₱0        → ₱0.50
        9999: 50, // ₱99.99    → ₱0.50
        10000: 100, // ₱100.00   → ₱1.00
        29999: 100, // ₱299.99   → ₱1.00
        30000: 200, // ₱300.00   → ₱2.00
        49999: 200, // ₱499.99   → ₱2.00
        50000: 300, // ₱500.00   → ₱3.00
        99999: 300, // ₱999.99   → ₱3.00
        100000: 500, // ₱1,000.00 → ₱5.00
        100001: 500, // ₱1,000.01 → ₱5.00
        5000000: 500, // ₱50,000   → ₱5.00
      };

      expectations.forEach((subtotalCentavos, expectedFeeCentavos) {
        final subtotal = Money.fromCentavos(subtotalCentavos);
        expect(
          schedule.feeFor(subtotal),
          Money.fromCentavos(expectedFeeCentavos),
          reason: 'subtotal ${subtotal.format()}',
        );
      });
    });

    test('the fee never jumps at a value no tier claims', () {
      // Sweep every centavo across the first three boundaries; a gap or overlap would
      // either throw or return the wrong band.
      for (var centavos = 0; centavos <= 50100; centavos++) {
        expect(
          () => schedule.feeFor(Money.fromCentavos(centavos)),
          returnsNormally,
        );
      }
    });

    test('tierFor reports the band that applied', () {
      final band = schedule.tierFor(const Money.fromCentavos(6250));
      expect(band.fee, const Money.fromCentavos(50));
      expect(band.rangeLabel, '₱0 – ₱99.99');
    });

    test('the open-ended tier reads clearly', () {
      expect(schedule.tiers.last.rangeLabel, '₱1,000 and above');
      expect(schedule.tiers.last.isOpenEnded, isTrue);
    });

    test('a negative subtotal is refused rather than silently charged', () {
      expect(
        () => schedule.feeFor(const Money.fromCentavos(-1)),
        throwsA(isA<GcashFeeConfigException>()),
      );
    });
  });

  group('the worked example from the specification', () {
    test('₱18.75 × 2 plus ₱25.00 pays one ₱0.50 fee, totalling ₱63.00', () {
      final lineA = const Money.fromCentavos(1875) * 2; // ₱37.50
      const lineB = Money.fromCentavos(2500); // ₱25.00
      final subtotal = lineA + lineB;
      expect(subtotal, const Money.fromCentavos(6250));

      final fee = schedule.feeFor(subtotal);
      expect(fee, const Money.fromCentavos(50));

      expect(subtotal + fee, const Money.fromCentavos(6300));
      expect((subtotal + fee).format(), '₱63');
    });

    test('a ₱56.25 subtotal pays ₱0.50, totalling ₱56.75', () {
      const subtotal = Money.fromCentavos(5625);
      expect(
        subtotal + schedule.feeFor(subtotal),
        const Money.fromCentavos(5675),
      );
    });

    test('the fee is charged once, not once per product', () {
      const unit = Money.fromCentavos(1875);
      final subtotal = unit * 4; // ₱75.00
      final total = subtotal + schedule.feeFor(subtotal);

      final perProductMistake = (unit + const Money.fromCentavos(50)) * 4;
      expect(total, const Money.fromCentavos(7550));
      expect(total, isNot(perProductMistake));
    });
  });

  group('validation', () {
    test('accepts the default schedule', () {
      expect(GcashFeeSchedule.describeProblem(schedule.tiers), isNull);
    });

    test('an empty table is refused', () {
      expect(GcashFeeSchedule.describeProblem([]), contains('at least one'));
    });

    test('overlapping tiers are refused', () {
      final problem = GcashFeeSchedule.describeProblem([
        tier(0, 10000, 50),
        tier(9000, null, 100),
      ]);
      expect(problem, contains('overlap'));
    });

    test('a gap between tiers is refused', () {
      final problem = GcashFeeSchedule.describeProblem([
        tier(0, 9999, 50),
        tier(20000, null, 100),
      ]);
      expect(problem, contains('Nothing covers'));
    });

    test('a table that does not start at zero is refused', () {
      final problem = GcashFeeSchedule.describeProblem([tier(100, null, 50)]);
      expect(problem, contains('must start at ₱0'));
    });

    test('a table with no open-ended tier is refused', () {
      final problem = GcashFeeSchedule.describeProblem([tier(0, 9999, 50)]);
      expect(problem, contains('no upper limit'));
    });

    test('an open-ended tier in the middle is refused', () {
      final problem = GcashFeeSchedule.describeProblem([
        tier(0, null, 50),
        tier(10000, null, 100),
      ]);
      expect(problem, contains('must be the last tier'));
    });

    test('negative minimums and fees are refused', () {
      expect(
        GcashFeeSchedule.describeProblem([tier(-100, null, 50)]),
        contains('below ₱0'),
      );
      expect(
        GcashFeeSchedule.describeProblem([tier(0, null, -50)]),
        contains('cannot be negative'),
      );
    });

    test('an inverted range is refused', () {
      final problem = GcashFeeSchedule.describeProblem([
        tier(0, 4999, 50),
        tier(5000, 4000, 100),
        tier(10000, null, 200),
      ]);
      expect(problem, contains('before it starts'));
    });

    test(
      'validated() throws with the same message describeProblem returns',
      () {
        final tiers = [tier(0, 9999, 50)];
        expect(
          () => GcashFeeSchedule.validated(tiers),
          throwsA(
            isA<GcashFeeConfigException>().having(
              (e) => e.message,
              'message',
              GcashFeeSchedule.describeProblem(tiers),
            ),
          ),
        );
      },
    );

    test('tiers given out of order are sorted rather than rejected', () {
      final built = GcashFeeSchedule.validated([
        tier(10000, null, 100),
        tier(0, 9999, 50),
      ]);
      expect(built.tiers.first.min, Money.zero);
      expect(
        built.feeFor(const Money.fromCentavos(5000)),
        const Money.fromCentavos(50),
      );
    });
  });

  group('serialisation', () {
    test('round-trips through Firestore', () {
      final restored = GcashFeeSchedule.fromJson(schedule.toJson());
      expect(restored, schedule);
    });

    test('a missing or empty document falls back to the default table', () {
      expect(GcashFeeSchedule.fromJson(null), GcashFeeSchedule.defaultSchedule);
      expect(
        GcashFeeSchedule.fromJson(const <Object>[]),
        GcashFeeSchedule.defaultSchedule,
      );
    });

    test('an open-ended tier keeps its null maximum', () {
      final json = schedule.toJson();
      expect(json.last['maxCentavos'], isNull);
      expect(GcashFeeSchedule.fromJson(json).tiers.last.isOpenEnded, isTrue);
    });

    test('copyWith can clear a maximum', () {
      final open = tier(0, 9999, 50).copyWith(max: null);
      expect(open.isOpenEnded, isTrue);
    });

    test('copyWith leaves the maximum alone when it is not passed', () {
      final unchanged = tier(
        0,
        9999,
        50,
      ).copyWith(fee: const Money.fromCentavos(75));
      expect(unchanged.max, const Money.fromCentavos(9999));
      expect(unchanged.fee, const Money.fromCentavos(75));
    });
  });
}
