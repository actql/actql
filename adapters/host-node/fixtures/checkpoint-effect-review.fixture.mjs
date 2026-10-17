// Explicit Preview-projection double for existing Checkpoint/lease tests whose
// physical Effect owner is already a double. It supplies no nominal Preview,
// Program capture, installation, permission or resource evidence. Actual
// original projection and public Host tests live in sealed-effect-review-*.
import {vectors,canonicalText} from '../../../scripts/fixtures/effect-review-projection-vectors.mjs';

export function checkpointEffectReviewDouble(control,previewCid){
  return (policy,limits)=>{
    const body={...vectors[0].body,effect_preview_cid:previewCid,
      authority_scope_cid:policy.authorityScopeCid,
      approval_claims:[...policy.approvalClaims],
      redaction_policy_cid:policy.redactionPolicyCid};
    return control.sealRunEvidence('review_projection',canonicalText(body),limits);
  };
}
