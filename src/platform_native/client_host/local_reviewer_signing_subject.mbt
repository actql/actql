///|
// Private identities for the same original logical request and opaque paired
// capture. Submission admission/scope stays with its independent original
// Owner; none of these four strings is a grant, signing permit or use claim.
fn NativeLocalReviewerProofMaterials::original_signing_subject(
  self : NativeLocalReviewerProofMaterials,
) -> Result[
  (String, String, String, String),
  NativeLocalReviewerProofMaterialsIssue,
] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
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
    Ok(read) => read.original_subject_after_current()
    Err(issue) => Err(issue)
  }
  // The terminal read above performs no callbacks. A last now/RunRead/key
  // callback cannot retire the original and leave a stale CID tuple successful.
  match subject {
    Ok((invocation, unit)) =>
      Ok((
        @host.client_request_intent_cid(reviewer.request),
        @host.client_request_scope_cid(reviewer.request),
        invocation,
        unit,
      ))
    Err(_) => Err(ProofUnavailable)
  }
}
