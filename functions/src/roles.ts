/**
 * Granting the owner role.
 *
 * The role lives in a Firebase Auth custom claim, because that is what Firestore security
 * rules can read. The mirror in `users/{uid}.role` is for the UI only, and the rules
 * refuse any client write that changes it.
 *
 * Bootstrapping is the awkward part: the first owner cannot be appointed by an existing
 * owner. {@link claimStoreOwnership} solves it with a setup code that is configured out of
 * band and works exactly once — after the first owner exists, it always refuses.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

import { asObject, auth, db, paths, requireAuth, requireOwner, requireString } from './lib/context';

/**
 * The one-time code that turns the first account into the store owner.
 *
 * Set before first deploy with:
 *
 *     firebase functions:secrets:set OWNER_SETUP_CODE
 *
 * For local development the emulator reads it from `functions/.secret.local`.
 */
const ownerSetupCode = defineSecret('OWNER_SETUP_CODE');

/** True once any account holds the owner role. */
async function ownerExists(): Promise<boolean> {
  const existing = await db
    .collection(paths.users)
    .where('role', '==', 'owner')
    .limit(1)
    .get();
  return !existing.empty;
}

async function grantRole(uid: string, role: 'customer' | 'cashier' | 'owner') {
  // The claim first: it is the authoritative copy, and the rules read it.
  await auth.setCustomUserClaims(uid, { role });
  await db.collection(paths.users).doc(uid).set(
    { role, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

/**
 * Turns the calling account into the store owner, once, using the setup code.
 *
 * Refuses if an owner already exists, so a leaked code cannot be replayed to mint a second
 * owner later. An anonymous account cannot claim ownership: the store owner needs a
 * credential they can sign back in with.
 */
export const claimStoreOwnership = onCall(
  { secrets: [ownerSetupCode] },
  async (request) => {
    const caller = requireAuth(request);
    const data = asObject(request.data);
    const code = requireString(data, 'setupCode', { maxLength: 200 });

    if (caller.isAnonymous) {
      throw new HttpsError(
        'failed-precondition',
        'Create an account with an email and password first, then claim the store.',
      );
    }

    const expected = ownerSetupCode.value();
    if (!expected) {
      throw new HttpsError(
        'failed-precondition',
        'No owner setup code is configured for this deployment.',
      );
    }
    if (code !== expected) {
      throw new HttpsError('permission-denied', 'That setup code is not correct.');
    }
    if (await ownerExists()) {
      throw new HttpsError(
        'failed-precondition',
        'This store already has an owner. Ask them to grant you access.',
      );
    }

    await grantRole(caller.uid, 'owner');

    // The caller keeps their old claims until their ID token refreshes, so tell the client
    // to force a refresh rather than leaving them looking at customer screens.
    return { uid: caller.uid, role: 'owner', refreshTokenRequired: true };
  },
);

/**
 * Grants or revokes the owner or cashier role for another account.
 *
 * Owner-only, and an owner cannot change their own role away from owner — a store with no
 * owner would have no way to price anything, change settings, or fulfil an order.
 */
export const setUserRole = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const targetEmail = requireString(data, 'email', { maxLength: 200 });
  const role = requireString(data, 'role', { maxLength: 20 });

  if (role !== 'owner' && role !== 'cashier' && role !== 'customer') {
    throw new HttpsError('invalid-argument', 'Role must be owner, cashier or customer.');
  }

  let targetUid: string;
  try {
    const user = await auth.getUserByEmail(targetEmail);
    targetUid = user.uid;
  } catch {
    throw new HttpsError('not-found', 'No account uses that email address.');
  }

  // Broadened from `role === 'customer'`: now that cashier is a valid role, an owner could
  // otherwise demote themselves to cashier and land the store in exactly the same
  // no-owner state this guard exists to prevent.
  if (targetUid === caller.uid && role !== 'owner') {
    throw new HttpsError(
      'failed-precondition',
      'You cannot remove your own owner access. Ask another owner to do it.',
    );
  }

  await grantRole(targetUid, role);
  return { uid: targetUid, role };
});
