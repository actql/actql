import {join} from 'node:path';
import {localHostStoreAuthorityCid} from './host-store-identity.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import {prepareOrdinaryLocalAccount} from './ordinary-local-account.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership,
  assertOriginalPreparedLocalPublicationStoreOwnership}
  from '../store-local/publication-store.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {preparePrivateEvidenceKeyInstallation} from './local-continuation-evidence.mjs';

// Publication may be the first operation on this Host root. Preserve that
// actual creation in the existing initializer before provider work can fail.
// The later Local Host adopts its Account and Store using their actual subjects.
// Existing roots gain no initialization authority. Account intent is never
// authority for the independent private-evidence key initializer.
export async function prepareInstalledPublicationRoot(root, principal) {
  const rootCreation = await admitHostRootFormat(root);
  if (rootCreation !== 'new') return;
  const original = await prepareLocalPublicationStoreOwnership(join(root, 'publication'));
  const publicationOwnership = Object.freeze({async close() {
    const state = await closePreparedLocalPublicationStoreOwnership(original);
    if (state?.pending !== false) {
      throw Object.assign(new Error('PublicationStoreCleanupPending'),
        {code: 'PublicationStoreCleanupPending'});
    }
  }});
  try {
    await prepareOrdinaryLocalAccount({root, principal, preparedOriginal: original, rootCreation});
    const storeDirectory = join(root, 'publication');
    const current = () => assertOriginalPreparedLocalPublicationStoreOwnership(original, storeDirectory);
    const storeAuthorityCid = localHostStoreAuthorityCid(root, principal);
    let keyInstallation;
    try {
      keyInstallation = await preparePrivateEvidenceKeyInstallation(join(root, 'checkpoints'), {
        storeDirectory, storeAuthorityCid, preparedOwnership: original, assertCurrent: current,
        assertFirstInitialization() {
          current();
          if (rootCreation !== 'new') {
            throw Object.assign(new Error('PrivateEvidenceFirstInitializationUnavailable'),
              {code: 'PrivateEvidenceFirstInitializationUnavailable'});
          }
        },
      });
    } finally {
      // Publication has no Store to adopt and no encrypted payload to retain.
      // Only the saved original generation passes to later normal Host startup.
      keyInstallation?.key.fill(0);
    }
    await publicationOwnership.close();
  } catch (cause) {
    // A failed Account/key initializer retains its original FD. Cleanup must ACK
    // before the same exclusion can retire; never release it in a finally.
    throw await retainInstalledHostInitializationFailure(cause, {publicationOwnership});
  }
}
