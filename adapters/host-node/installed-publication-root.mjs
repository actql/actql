import {join} from 'node:path';
import {admitHostRootFormat} from './host-root-format.mjs';
import {prepareOrdinaryLocalAccount} from './ordinary-local-account.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
  from '../store-local/publication-store.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

// Publication may be the first operation on this Host root. Preserve that
// actual creation in the existing initializer before provider work can fail.
// This records only pending intent: the later Local Host adopts its Account
// using its actual subjects. Existing roots gain no initialization authority.
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
    await publicationOwnership.close();
  } catch (cause) {
    // A failed intent writer retains its original FD. Its cleanup must ACK
    // before the same exclusion can retire; never release it in a finally.
    throw await retainInstalledHostInitializationFailure(cause, {publicationOwnership});
  }
}
