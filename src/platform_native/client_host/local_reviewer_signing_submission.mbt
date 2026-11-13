///|
// Authenticated retained Submission/Run identity, not an incoming CID getter.
// Called only after this Owner's complete material check, with no intervening
// callback or physical/Journal I/O. Pure original-lifetime comparisons do not
// reopen it. The final material check runs on successful and failed lookups.
fn NativeLocalReviewerProofMaterials::original_signing_submission_scope_after_current(
  self : NativeLocalReviewerProofMaterials,
) -> Result[String, NativeLocalReviewerProofMaterialsIssue] {
  let reviewer = self.reviewer
  // Only the initial key's SAME current captured Read may supply immutable
  // Host material. A configured/legacy caller retains its complete old path;
  // a selected expired or foreign capture must refuse rather than fall back.
  let capture = if self.key is InitialReviewerKey(key) &&
    reviewer.approval_scope is SavedApproval(saved) &&
    key.original.original_read is Some((capture, _)) {
    if !physical_equal(saved.capture, capture) {
      return Err(ProofUnavailable)
    }
    match key.original.check_host_current() {
      Ok(_) => ()
      Err(issue) => return Err(ProofKey(SigningCustody(issue)))
    }
    Some(capture)
  } else {
    None
  }
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
        capture~,
        fresh_account=true,
      ) {
      Ok(value) => value
      Err(issue) => return Err(ProofOriginal(issue))
    }
    let original = match
      reviewer.host.journal.lookup_submitted_intent(
        reviewer.host.epoch,
        reviewer.reference,
        authority.scope,
        authority.current_signing_for(reviewer.host.journal, reviewer.request),
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
