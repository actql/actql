///|
/// Read metadata only from this Review's original retained request and paired
/// Checkpoint/capture. Disclosure permission is independently installed; these
/// identities issue no grant, signing claim, approval or execution authority.
pub fn NativeResidentEffectReview::original_signing_subject(
  self : NativeResidentEffectReview,
  authorize_evidence_read : () -> Bool,
) -> Result[
  (String, String, String, String),
  NativeResidentEffectReviewIssue,
] {
  if self.closed || self.retiring || !self.current() ||
    !authorize_evidence_read() {
    return Err(Unavailable)
  }
  guard self.retention is Some(retention) else { return Err(Unavailable) }
  let report = match retention.report() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let approval = match retention.original_approval_scope() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let read = match
    approval.read_original_signing_subject_for(
      self.request,
      @publication.publication_contract_identity(self.materials.run_definition),
      @remote.remote_effect_checkpoint_report_checkpoint(report).checkpoint_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  // Owner/current and installed disclosure callbacks can retire the same
  // capture reentrantly. Keep the opaque read until all callbacks have ended.
  let disclosure_current = authorize_evidence_read()
  let owner_current = self.current()
  if !owner_current || !disclosure_current || self.closed || self.retiring {
    return Err(Unavailable)
  }
  guard self.retention is Some(actual) && physical_equal(actual, retention) else {
    return Err(Unavailable)
  }
  let (invocation, unit) = match read.original_subject_after_current() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  // No clock, authorization, Store or other current callback follows this
  // terminal lifetime check. Logical request and Submission remain distinct.
  Ok(
    (
      @host.client_request_intent_cid(self.request),
      @host.client_request_scope_cid(self.request),
      invocation,
      unit,
    ),
  )
}
