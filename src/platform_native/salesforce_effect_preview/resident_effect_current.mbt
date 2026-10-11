///|
/// Answer only from this original review's checked row and physical Ledger.
/// The authenticated control transport separately checks delegation/generation;
/// this method grants no send, approval or release permission.
pub fn NativeResidentEffectReview::answer_effect_current(
  self : NativeResidentEffectReview,
  query : @remote.RemoteEffectCurrentQuery,
  authorize_evidence_read : () -> Bool,
  limits : @checkpoint.WireLimits,
) -> Result[
  @remote.RemoteEffectCurrentReply,
  NativeResidentEffectObservationIssue,
] {
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  // The installed policy was admitted against this exact checked member at
  // review preparation. Refuse a different requested member before Store I/O.
  if @remote.remote_effect_current_query_effect_id(query) !=
    self.policy.effect_id {
    return Err(Row(ForeignRequest))
  }
  guard self.retention is Some(retention) && retention.report() is Ok(original) else {
    return Err(Unavailable)
  }
  let offered = @remote.remote_effect_current_query_report(query)
  if @remote.remote_effect_checkpoint_report_identity(offered) !=
    @remote.remote_effect_checkpoint_report_identity(original) ||
    @remote.remote_effect_checkpoint_report_json(offered) !=
    @remote.remote_effect_checkpoint_report_json(original) {
    return Err(Row(ForeignRequest))
  }
  let observed = match
    self.observe_effect_custody(authorize_evidence_read, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @remote.remote_effect_current_query_effect_id(query) != observed.effect_id {
    return Err(Row(ForeignRequest))
  }
  let reply = match
    @remote.prepare_remote_effect_current_reply(
      query,
      observed.ledger_head_cid,
      observed.recovery_action,
      observed.response_saved,
      limits,
    ) {
    Ok(value) => value
    Err(_) => return Err(Row(ForeignRequest))
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.closed {
    return Err(Unavailable)
  }
  Ok(reply)
}
