///|
/// Prepare only the existing unsigned Resolution proof against this Review's
/// retained original Checkpoint. A proposed body cannot choose the Checkpoint,
/// request, Invocation or explicit Unit. The returned subject is metadata at
/// this read boundary, not current signing permission, a use claim or Approval.
/// Caller workspace/control funding and every subsequent signing/current fence
/// remain separate; this does not install a key or renew retained custody.
pub fn NativeResidentEffectReview::prepare_original_resolution_proof(
  self : NativeResidentEffectReview,
  unsigned_wire : String,
  authorize_evidence_read : () -> Bool,
) -> Result[
  (@checkpoint.PreparedResolutionProof, (String, String, String, String)),
  NativeResidentEffectResolutionIssue,
] {
  if self.closed ||
    self.retiring ||
    !self.current() ||
    !authorize_evidence_read() {
    return Err(Unavailable)
  }
  guard self.retention is Some(retention) &&
    self.retention_configuration is Some((_, _, _, _, _, limits)) else {
    return Err(Unavailable)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
  let approval = match retention.original_approval_scope() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let read = match
    approval.read_original_signing_subject_for(
      self.request,
      @publication.publication_contract_identity(self.materials.run_definition),
      checkpoint.checkpoint_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let proof = match
    @checkpoint.prepare_resolution_proof(checkpoint, unsigned_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(Resolution(issue))
  }
  // Installed disclosure and existing Owner callbacks can retire the original
  // capture reentrantly. Finish every callback before the opaque lifetime read.
  let disclosure_current = authorize_evidence_read()
  let owner_current = self.current()
  if !disclosure_current || !owner_current || self.closed || self.retiring {
    return Err(Unavailable)
  }
  guard self.retention is Some(actual) && physical_equal(actual, retention) else {
    return Err(Unavailable)
  }
  let (invocation, unit) = match read.original_subject_after_current() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  // No current callback follows the terminal original-custody check. Local
  // Host adoption/Submission and Remote runtime facts are not interchangeable.
  Ok(
    (
      proof,
      (
        @host.client_request_intent_cid(self.request),
        @host.client_request_scope_cid(self.request),
        invocation,
        unit,
      ),
    ),
  )
}
