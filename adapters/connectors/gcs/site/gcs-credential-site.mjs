// The installed GCS Source and its published collection borrow the same
// credential Site. An Effect target read still needs its original Checkpoint
// decision/current entry; the installation predicate is not that authority.
import {openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';

export function openGcsCredentialSite(options) {
  return openRowSourceCredentialSite({...options,
    admitsEffectTargetRead:gcsEffectTargetRead(options.admitsApprovalTarget)});
}

// One installation predicate, never a target-read grant or write approval.
export function gcsEffectTargetRead(admitsApprovalTarget) {
  return (binding,resource,operation)=>resource==='objects'&&operation==='gcs:file:read'&&
    admitsApprovalTarget(binding,resource)===true;
}
