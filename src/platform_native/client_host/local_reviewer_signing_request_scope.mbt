///|
// Read-only subject fence for a candidate Reviewer scope, not complete grant
// admission or a signing permit. Issuer, key original, attempt,
// expiry, durable claim and outcome must pass their separate existing Owners.
// Submission uses its authenticated retained reference, not the logical scope.
fn NativeLocalReviewerProofMaterials::read_original_reviewer_signing_subject_after_current(
  self : NativeLocalReviewerProofMaterials,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[
  NativeLocalOriginalEffectSigningSubjectRead,
  NativeLocalReviewerProofMaterialsIssue,
] {
  // The enclosing scope reader has checked this same material and key. The
  // actual subject read owns its current callbacks, followed by the complete
  // material fence below; no fresh proof/current ticket is issued here.
  let reviewer = self.reviewer
  let projected = reviewer.approval_scope.read_original_signing_subject_for(
    reviewer.request,
    reviewer.original.run_definition_cid,
    self.original.artifact.checkpoint_cid,
  )
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let read = match projected {
    Ok(value) => value
    Err(_) => return Err(ProofUnavailable)
  }
  let (invocation, unit) = match read.original_subject_after_current() {
    Ok(value) => value
    Err(_) => return Err(ProofUnavailable)
  }
  let request = @host.client_request_intent_cid(reviewer.request)
  let logical_scope = @host.client_request_scope_cid(reviewer.request)
  let submission = match
    self.original_signing_submission_scope_after_current() {
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
  // Submission's final complete material check already follows its last
  // callback, including the mismatch path. All comparisons above are immutable;
  // retain the same subject's noncallback lifetime fence rather than introduce
  // another full current/RunRead/clock round trip.
  // No callback follows this existing Owner's terminal reference/lifetime
  // check, including on a subject mismatch. It neither recaptures originals
  // nor acquires signing permission, a grant or a renewed reservation.
  match read.original_subject_after_current() {
    Ok((after_invocation, after_unit)) if same_subject &&
      after_invocation == invocation &&
      after_unit == unit => Ok(read)
    Ok(_) | Err(_) => Err(ProofUnavailable)
  }
}
