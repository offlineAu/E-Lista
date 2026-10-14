import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { HttpsError } from 'firebase-functions/v2/https';

import { requireAuth, requireOwner, requireOwnerOrCashier } from '../src/lib/context';

/** Enough of a `CallableRequest` for these guards, which only read `request.auth`. */
function fakeRequest(claims: Record<string, unknown> = {}) {
  return { auth: { uid: 'uid-1', token: claims } } as unknown as Parameters<
    typeof requireAuth
  >[0];
}

describe('requireAuth role derivation', () => {
  it('rejects a request with no auth context at all', () => {
    assert.throws(
      () => requireAuth({ auth: undefined } as unknown as Parameters<typeof requireAuth>[0]),
      HttpsError,
    );
  });

  it('reads no role claim as a plain customer', () => {
    assert.equal(requireAuth(fakeRequest()).role, 'customer');
  });

  it('reads an owner claim', () => {
    assert.equal(requireAuth(fakeRequest({ role: 'owner' })).role, 'owner');
  });

  it('reads a cashier claim', () => {
    assert.equal(requireAuth(fakeRequest({ role: 'cashier' })).role, 'cashier');
  });

  it('an anonymous sign-in is a guest regardless of any role claim', () => {
    // Mirrors claimStoreOwnership's own isAnonymous check: owner/cashier only ever mean
    // something for a real credential.
    const request = fakeRequest({
      role: 'cashier',
      firebase: { sign_in_provider: 'anonymous' },
    });
    assert.equal(requireAuth(request).role, 'guest');
  });

  it('an unrecognised role claim falls back to customer, not to staff', () => {
    assert.equal(requireAuth(fakeRequest({ role: 'superuser' })).role, 'customer');
  });
});

describe('requireOwner', () => {
  it('admits an owner', () => {
    assert.equal(requireOwner(fakeRequest({ role: 'owner' })).role, 'owner');
  });

  it('refuses a cashier', () => {
    assert.throws(() => requireOwner(fakeRequest({ role: 'cashier' })), HttpsError);
  });

  it('refuses a plain customer', () => {
    assert.throws(() => requireOwner(fakeRequest()), HttpsError);
  });
});

describe('requireOwnerOrCashier', () => {
  it('admits an owner', () => {
    assert.equal(requireOwnerOrCashier(fakeRequest({ role: 'owner' })).role, 'owner');
  });

  it('admits a cashier', () => {
    assert.equal(requireOwnerOrCashier(fakeRequest({ role: 'cashier' })).role, 'cashier');
  });

  it('refuses a plain customer', () => {
    assert.throws(() => requireOwnerOrCashier(fakeRequest()), HttpsError);
  });

  it('refuses a guest', () => {
    const request = fakeRequest({ firebase: { sign_in_provider: 'anonymous' } });
    assert.throws(() => requireOwnerOrCashier(request), HttpsError);
  });
});
