// The installed GCS Source and its published collection borrow the same
// credential Site. An Effect target read still needs its original Checkpoint
// decision/current entry; the installation predicate is not that authority.
import {openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';

export function openGcsCredentialSite(options) {
  const admitsApprovalTarget = options.admitsApprovalTarget;
  return openRowSourceCredentialSite({...options,
    // Upload preparation reads metadata of this installed objects collection.
    // Do not turn a write approval, a files/contents Source, or another GCS
    // operation into that read. The existing exact physical scope predicate
    // remains the single installation check for both Source and Effect reads.
    admitsEffectTargetRead: (binding, resource, operation) =>
      resource === 'objects' && operation === 'gcs:file:read' &&
      admitsApprovalTarget(binding, resource) === true});
}
