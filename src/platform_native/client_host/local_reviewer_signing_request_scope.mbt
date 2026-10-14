///|
// Read-only subject fence for a candidate Reviewer scope, not complete grant
// admission or a signing permit. Issuer, key original, attempt,
// expiry, durable claim and outcome must pass their separate existing Owners.
// Submission uses its authenticated retained reference, not the logical scope.
fn NativeLocalReviewerProofMaterials::require_original_reviewer_signing_subject(
  self : NativeLocalReviewerProofMaterials,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[Unit, NativeLocalReviewerProofMaterialsIssue] {
  // This projection reads the authentic paired capture, original checked Unit
  // and logical request, with current Client/Reviewer/key/control fences.
  let (request, logical_scope, invocation, unit) = match
    self.original_signing_subject() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let submission = match self.original_signing_submission_scope() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let checkpoint = self.original.artifact
  let same_subject = scope.purpose == @credential.ReviewerProof &&
    scope.request_cid == request &&
    scope.request_scope_cid == logical_scope &&
    scope.submission_scope_cid == submission &&
    scope.run_invocation_cid == invocation &&
    scope.unit_definition_cid == unit &&
    scope.run_definition_cid == self.reviewer.original.run_definition_cid &&
    scope.checkpoint_cid == checkpoint.checkpoint_cid &&
    scope.checkpoint_id == checkpoint.checkpoint.checkpoint_id &&
    scope.checkpoint_kind == checkpoint.checkpoint.kind &&
    scope.preimage == self.proof.preimage()
  // Re-read the same original and actual current authorization after comparison,
  // including the mismatch path. A stale revision/current denial keeps priority;
  // no preparation, capture, unsigned proof, grant or use is reissued.
  match self.require_current() {
    Err(issue) => Err(issue)
    Ok(_) =>
      if same_subject {
        Ok(())
      } else {
        Err(ProofUnavailable)
      }
  }
}
