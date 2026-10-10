///|
/// Evidence from the original paired report and one existing Ledger snapshot.
/// It contains neither response bytes, approval, a send permit nor cleanup proof.
pub struct NativeResidentEffectObservation {
  dispatch_request_cid : String
  report_cid : String
  checkpoint_cid : String
  effect_id : String
  ledger_head_cid : String?
  recovery_action : Int
  response_saved : Bool
  priv unknown_effects : Array[String]
}

///|
/// Return a copy so a caller cannot erase this snapshot's unresolved outcomes.
pub fn NativeResidentEffectObservation::unknown_effects(
  self : NativeResidentEffectObservation,
) -> Array[String] {
  self.unknown_effects.copy()
}

///|
pub(all) enum NativeResidentEffectObservationIssue {
  Unavailable
  EvidenceDenied
  Report(NativeResidentEffectReviewUploadIssue)
  Row(NativeResidentEffectWriteIssue)
}

///|
fn native_effect_unknowns_for_action(
  effect_id : String,
  action : Int,
) -> Result[Array[String], NativeResidentEffectWriteIssue] {
  // Classify the common recovery Owner's result, never infer outcome from a
  // missing network response or local dispatch flag. No action permits I/O.
  match action {
    0 | 1 | 5 | 6 | 7 => Ok([])
    3 | 4 => Ok([effect_id])
    _ => Err(ForeignRequest)
  }
}

///|
/// Observe original row responsibility through the existing physical journal.
/// Historical evidence access is independent of current write permission.
/// Missing/failed/corrupt Store custody returns an error, never an empty outcome
/// inventory. Ledger absence is admitted only for the exact checked row, in the
/// journal transaction that also checks original dispatch/report binding.
pub fn NativeResidentEffectReview::observe_effect_custody(
  self : NativeResidentEffectReview,
  authorize_evidence_read : () -> Bool,
  limits : @checkpoint.WireLimits,
) -> Result[
  NativeResidentEffectObservation,
  NativeResidentEffectObservationIssue,
] {
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  guard !self.closed &&
    self.retention is Some(retention) &&
    self.retention_configuration is Some((_, _, _, _, _, report_limits)) else {
    return Err(Unavailable)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  match self.confirm_original_review_report(report, report_limits, true) {
    Ok(_) => ()
    Err(issue) => return Err(Report(issue))
  }
  let context = match self.row_context(limits) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  guard @publication.effect_preview_member_effect_id(context.preview, 0)
    is Some(effect_id) else {
    return Err(Row(ForeignRequest))
  }
  let custody = match self.restore_row_custody(limits) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  let head = custody.map(value => value.head)
  // A read-only observer does not claim the active execution. Dispatching is
  // therefore the common Owner's conservative possible-dispatch observation.
  let action = @effect.effect_row_recovery_action_from_entry(
    context.locator,
    context.basis.intent_fingerprint_cid,
    context.key,
    context.basis.canonical_request_cid,
    head,
    false,
  )
  let unknown = match native_effect_unknowns_for_action(effect_id, action) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  // Check the same report ACK again after Store access and before disclosure.
  match self.confirm_original_review_report(report, report_limits, true) {
    Ok(_) => ()
    Err(issue) => return Err(Report(issue))
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.closed {
    return Err(Unavailable)
  }
  Ok({
    dispatch_request_cid: @remote.dispatch_request_identity(
      @remote.remote_effect_checkpoint_report_dispatch(report),
    ),
    report_cid: @remote.remote_effect_checkpoint_report_identity(report),
    checkpoint_cid: @remote.remote_effect_checkpoint_report_checkpoint(report).checkpoint_cid,
    effect_id,
    ledger_head_cid: head.map(@effect.effect_ledger_entry_cid),
    recovery_action: action,
    response_saved: custody is Some({ response: Some(_), .. }),
    unknown_effects: unknown,
  })
}
