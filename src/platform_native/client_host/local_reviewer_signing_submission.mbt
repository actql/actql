///|
// Identity from the authenticated retained Submission/Run admission, never
// from the incoming reference's getter alone. History lookup does not renew an
// epoch, authorize a new start or provide signing eligibility.
fn NativeLocalReviewerProofMaterials::original_signing_submission_scope(
  self : NativeLocalReviewerProofMaterials,
) -> Result[String, NativeLocalReviewerProofMaterialsIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let reviewer = self.reviewer
  // Keep the large retained intent/admission inside this read phase; only its
  // existing Submission identity is returned to the final current fence.
  let read = fn() -> Result[String, NativeLocalReviewerProofMaterialsIssue] {
    let authority = match
      native_local_policy_authority_for(
        reviewer.host,
        reviewer.crypto,
        reviewer.principal,
        reviewer.connection,
        reviewer.request,
        ReadRunMaterials,
      ) {
      Ok(value) => value
      Err(issue) => return Err(ProofOriginal(issue))
    }
    let original = match
      reviewer.host.journal.lookup_submitted_intent(
        reviewer.host.epoch,
        reviewer.reference,
        authority.scope,
        authority.current_for(reviewer.host.journal, reviewer.request),
        (reviewer.now)(),
      ) {
      Ok(Submitted(value)) => value
      Ok(UnresolvedSubmissionHistory) => return Err(ProofUnavailable)
      Err(issue) => return Err(ProofOriginal(issue))
    }
    guard original.run_admission is Some(admission) else {
      return Err(ProofUnavailable)
    }
    if @host.client_request_identity_relation(
        admission.request,
        reviewer.request,
      ) !=
      @host.SameRequest ||
      admission.run_definition_cid != reviewer.original.run_definition_cid ||
      native_client_submission_reference_wire(original.reference) !=
      native_client_submission_reference_wire(reviewer.reference) ||
      native_client_submission_request_id(original.reference) !=
      @host.client_request_caller_id(admission.request) {
      return Err(ProofUnavailable)
    }
    Ok(native_client_submission_request_id(original.reference))
  }
  let projected = read()
  // Original Client RunRead, Reviewer/key custody, same Checkpoint and control
  // revision are independently re-read even on lookup/identity failure. These
  // separate journal reads are not advertised as an atomic snapshot.
  match self.require_current() {
    Err(issue) => Err(issue)
    Ok(_) => projected
  }
}
