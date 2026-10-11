///|
/// A query/report transport failure retains the original review and Ledger;
/// none of these results is authority to resend a Provider operation.
pub(all) enum NativeResidentEffectCurrentReportIssue {
  Unavailable
  EvidenceDenied
  Query(@remote.DispatchIssue)
  Observation(NativeResidentEffectObservationIssue)
  Transport(@client.NativeRemoteClientIssue)
}

///|
/// Admit the query against this Owner's paired original report, observe the
/// physical Ledger through the existing review Owner, and send its opaque
/// reply over the authenticated observation transport. The caller installs
/// current evidence-read authority independently of approval/write authority.
/// A 200 response is a transport receipt only, never a durable Effect ACK.
pub fn NativeResidentEffectReview::report_effect_current(
  self : NativeResidentEffectReview,
  body : String,
  client : @http.Client,
  url : String,
  authorize_evidence_read : () -> Bool,
  limits : @checkpoint.WireLimits,
) -> Result[
  @remote.RemoteEffectCurrentReply,
  NativeResidentEffectCurrentReportIssue,
] {
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  guard !self.closed &&
    self.retention is Some(retention) &&
    retention.report() is Ok(original) else {
    return Err(Unavailable)
  }
  let query = match
    @remote.admit_remote_effect_current_query_json(body, original, limits) {
    Ok(value) => value
    Err(issue) => return Err(Query(issue))
  }
  let reply = match
    self.answer_effect_current(query, authorize_evidence_read, limits) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.closed {
    return Err(Unavailable)
  }
  match @client.acknowledge_effect_current(client, url, reply) {
    Ok(_) => ()
    Err(issue) => return Err(Transport(issue))
  }
  // I/O may outlive local disclosure authority or the original report's
  // custody. Preserve the transport fact, but return no current reply under
  // a revoked read capability. This never rolls back or resends a write.
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.closed {
    return Err(Unavailable)
  }
  match self.confirm_original_review_report(original, limits, true) {
    Ok(_) => Ok(reply)
    Err(issue) => Err(Observation(Report(issue)))
  }
}
