///|
// Private identities for the same original logical request and opaque paired
// capture. Submission admission/scope stays with its independent original
// Owner; this read view is not a grant, signing permit or use claim.
fn NativeLocalReviewerProofMaterials::read_original_signing_subject_after_current(
  self : NativeLocalReviewerProofMaterials,
) -> Result[
  NativeLocalOriginalEffectSigningSubjectRead,
  NativeLocalReviewerProofMaterialsIssue,
] {
  // The enclosing scope constructor has just checked this same material.
  // Only immutable attempt syntax separates that check from this read.
  let reviewer = self.reviewer
  let projected = reviewer.approval_scope.read_original_signing_subject_for(
    reviewer.request,
    reviewer.original.run_definition_cid,
    self.original.artifact.checkpoint_cid,
  )
  // Original Client RunRead, configured Reviewer/key and the same control
  // revision are checked after the separate Store/capture observations too.
  // This is not one transaction across those existing Owners.
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let subject = match projected {
    Ok(read) => read
    Err(_) => return Err(ProofUnavailable)
  }
  // Retain the actual subject across the remaining Submission/clock callbacks;
  // a tuple alone cannot detect retirement of these same original references.
  subject
  .original_subject_after_current()
  .map(_ => subject)
  .map_err(_ => ProofUnavailable)
}
