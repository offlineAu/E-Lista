/**
 * GCash convenience fee tiers.
 *
 * The fee is charged **once per transaction**, never once per product. Which fee applies
 * depends on the GCash product subtotal (before the fee itself is added).
 *
 * Tiers are owner-configurable and stored in Firestore at `settings/gcash_fees` — they are
 * never hard-coded into a UI. This module owns the shape, the validation and the lookup;
 * `lib/features/pricing/domain/gcash_fee_schedule.dart` is its Dart mirror.
 */

import { MoneyError, assertInteger, formatCentavos } from './money';

export interface GcashFeeTier {
  /** Inclusive lower bound of the subtotal range, in centavos. */
  minCentavos: number;
  /**
   * Inclusive upper bound in centavos, or `null` for the open-ended top tier.
   * `₱0 – ₱99.99` is `{minCentavos: 0, maxCentavos: 9999}`.
   */
  maxCentavos: number | null;
  /** The flat fee charged for this tier, in centavos. */
  feeCentavos: number;
}

/**
 * The tiers a new store starts with. They are written to Firestore on first run and are
 * fully editable afterwards; nothing in the app reads these constants at checkout time.
 */
export const DEFAULT_GCASH_FEE_TIERS: readonly GcashFeeTier[] = [
  { minCentavos: 0, maxCentavos: 9999, feeCentavos: 50 },
  { minCentavos: 10000, maxCentavos: 29999, feeCentavos: 100 },
  { minCentavos: 30000, maxCentavos: 49999, feeCentavos: 200 },
  { minCentavos: 50000, maxCentavos: 99999, feeCentavos: 300 },
  { minCentavos: 100000, maxCentavos: null, feeCentavos: 500 },
];

export class GcashFeeConfigError extends Error {}

/**
 * Validates a tier list and returns it sorted by lower bound.
 *
 * A schedule is only usable if every possible subtotal resolves to exactly one fee, so
 * this rejects negative values, inverted ranges, overlaps and gaps, and requires that the
 * schedule starts at ₱0 and ends with an open-ended tier.
 */
export function normaliseGcashFeeTiers(tiers: readonly GcashFeeTier[]): GcashFeeTier[] {
  if (tiers.length === 0) {
    throw new GcashFeeConfigError('At least one GCash fee tier is required.');
  }

  const sorted = [...tiers].sort((a, b) => a.minCentavos - b.minCentavos);

  sorted.forEach((tier, index) => {
    const label = `Tier ${index + 1}`;
    try {
      assertInteger(tier.minCentavos, `${label} minimum`);
      assertInteger(tier.feeCentavos, `${label} fee`);
      if (tier.maxCentavos !== null) {
        assertInteger(tier.maxCentavos, `${label} maximum`);
      }
    } catch (error) {
      throw new GcashFeeConfigError((error as MoneyError).message);
    }

    if (tier.minCentavos < 0) {
      throw new GcashFeeConfigError(`${label} minimum cannot be negative.`);
    }
    if (tier.feeCentavos < 0) {
      throw new GcashFeeConfigError(`${label} fee cannot be negative.`);
    }
    if (tier.maxCentavos !== null && tier.maxCentavos < tier.minCentavos) {
      throw new GcashFeeConfigError(
        `${label} ends at ${formatCentavos(tier.maxCentavos)} which is before it starts ` +
          `at ${formatCentavos(tier.minCentavos)}.`,
      );
    }
    if (tier.maxCentavos === null && index !== sorted.length - 1) {
      throw new GcashFeeConfigError(
        `${label} is open-ended, so it must be the last tier.`,
      );
    }
  });

  if (sorted[0].minCentavos !== 0) {
    throw new GcashFeeConfigError('The first tier must start at ₱0.');
  }
  if (sorted[sorted.length - 1].maxCentavos !== null) {
    throw new GcashFeeConfigError(
      'The last tier must be open-ended so that every order total has a fee.',
    );
  }

  for (let i = 1; i < sorted.length; i++) {
    const previous = sorted[i - 1];
    const current = sorted[i];
    // `previous.maxCentavos` is non-null: only the final tier may be open-ended.
    const expected = (previous.maxCentavos as number) + 1;
    if (current.minCentavos < expected) {
      throw new GcashFeeConfigError(
        `Tier ${i} and tier ${i + 1} overlap around ${formatCentavos(current.minCentavos)}.`,
      );
    }
    if (current.minCentavos > expected) {
      throw new GcashFeeConfigError(
        `No tier covers ${formatCentavos(expected)} — tiers must not leave gaps.`,
      );
    }
  }

  return sorted;
}

/**
 * Resolves the single fee for a GCash subtotal. `tiers` must already be normalised, which
 * guarantees a match for every non-negative subtotal.
 */
export function resolveGcashFeeCentavos(
  subtotalCentavos: number,
  tiers: readonly GcashFeeTier[],
): number {
  assertInteger(subtotalCentavos, 'subtotal');
  if (subtotalCentavos < 0) {
    throw new MoneyError('subtotal cannot be negative');
  }
  const match = tiers.find(
    (tier) =>
      subtotalCentavos >= tier.minCentavos &&
      (tier.maxCentavos === null || subtotalCentavos <= tier.maxCentavos),
  );
  if (!match) {
    throw new GcashFeeConfigError(
      `No GCash fee tier covers ${formatCentavos(subtotalCentavos)}.`,
    );
  }
  return match.feeCentavos;
}
