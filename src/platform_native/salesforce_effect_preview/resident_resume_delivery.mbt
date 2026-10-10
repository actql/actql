///|
/// Deliver the original approved Resolution through the existing review,
/// signature, Ledger and current resume-fence Owners. The wire's claim is
/// never converted into an observation or permission. The trusted read port
/// must independently confirm that exact claim before preparation and every
/// subsequent Provider send. Historical saved-response settlement keeps its
/// existing Ledger custody rules; it does not renew permission to send.
pub fn NativeResidentEffectReview::prepare_remote_approved_row(
  self : NativeResidentEffectReview,
  body : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  keys : Array[NativeEffectHostAuthority],
  current_authority : () -> Bool,
  observe_resume : () -> NativeEffectResumeObservation?,
  now : () -> String,
  limits : NativeResidentEffectWriteLimits,
) -> Result[NativeResidentEffectApprovedRow, NativeResidentEffectWriteIssue] {
  guard current_authority() &&
    self.current() &&
    self.retention is Some(retention) &&
    self.retention_configuration is Some((_, _, _, _, _, checkpoint_limits)) else {
    return Err(AuthorityDenied)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  // The paired original must already have its exact durable typed ACK. A
  // signed Resolution cannot discharge an outstanding report/ACK obligation.
  if self.confirm_original_review_report(report, checkpoint_limits, true)
    is Err(_) {
    return Err(Unavailable)
  }
  let delivery = match
    @remote.admit_remote_effect_resume_delivery_json(
      body, report, authentication, reviewers, checkpoint_limits,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignRequest)
  }
  let resolution = @remote.remote_effect_resume_delivery_resolution(delivery)
  let claim = @remote.remote_effect_resume_delivery_claim(delivery)
  // Capture the admitted immutable identity. Do not let an old envelope use
  // a later lease, another claimant, or a settlement-only observation to send.
  let observed_current = () => {
    match observe_resume() {
      Some(observed) if observed.checkpoint_cid == resolution.checkpoint_cid &&
        observed.resolution_cid == resolution.resolution_cid &&
        Some(observed.resume_intent_id) == resolution.resume_intent_id &&
        observed.claim == claim &&
        !observed.settlement_only &&
        @checkpoint.decide_resume_fence(
          observed.view,
          observed.claim,
          observed.now_ms,
        ) ==
        @checkpoint.FenceCurrent => Some(observed)
      _ => None
    }
  }
  if observed_current() is None || !current_authority() || !self.current() {
    return Err(AuthorityDenied)
  }
  // Keep this exact delivery claim in the existing row Owner for later sends.
  // Historical saved-response settlement remains separate from renewed send
  // authority. Preparation itself never sends a write.
  self.prepare_approved_row(
    resolution.wire,
    authentication,
    reviewers,
    keys,
    current_authority,
    observed_current,
    now,
    limits,
    delivery_claim=Some(claim),
  )
}
