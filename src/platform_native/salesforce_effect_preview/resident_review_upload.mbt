///|
pub(all) enum NativeResidentEffectReviewUploadIssue {
  Review(NativeResidentEffectReviewIssue)
  Report(@client.NativeRemoteClientIssue)
  Http(@http.NativeHttpIssue)
  HttpStatus(Int)
  InvalidResponse
}

///|
/// Send the exact confirmed original projection to the configured Cloud
/// artifact URL after the existing journal/client Owner confirms the original
/// report's typed ACK. The Client supplies its existing Site credential; the header
/// comes from the original typed report, never a caller-proposed identity.
/// A 204 confirms artifact save only, not report ACK, approval or release.
/// Failure/uncertainty leaves all existing custody live for explicit retry.
pub fn NativeResidentEffectReview::upload_review_projection(
  self : NativeResidentEffectReview,
  client : @http.Client,
  report_url : String,
  url : String,
  authorize_evidence_read : () -> Bool,
) -> Result[Unit, NativeResidentEffectReviewUploadIssue] {
  let (report, wire) = match
    self.review_projection(authorize_evidence_read, 65536) {
    Ok(value) => value
    Err(issue) => return Err(Review(issue))
  }
  let dispatch = @remote.remote_effect_checkpoint_report_dispatch(report)
  // A bare HTTP success is not a Checkpoint ACK. The existing client admits
  // the exact report-bound reply and durably saves it in the same journal;
  // an already accepted receipt performs no further report transmission.
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
  match
    @client.acknowledge_retained_effect_checkpoint(
      self.journal,
      client,
      report_url,
      dispatch,
      limits,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Report(issue))
  }
  // The remote ACK may be durable even if local disclosure authority changed
  // during I/O. Preserve that fact, but do not send the review under stale
  // authority or replace its original report with a newer projection.
  let (confirmed_report, confirmed_wire) = match
    self.review_projection(authorize_evidence_read, 65536) {
    Ok(value) => value
    Err(issue) => return Err(Review(issue))
  }
  if confirmed_wire != wire ||
    @remote.remote_effect_checkpoint_report_identity(confirmed_report) !=
    @remote.remote_effect_checkpoint_report_identity(report) {
    return Err(InvalidResponse)
  }
  let headers : Array[@http.NativeHttpHeader] = [
    { name: "content-type", value: "application/json", },
    {
      name: "actql-dispatch-cid",
      value: @remote.dispatch_request_identity(dispatch),
    },
  ]
  let response = match client.request(Post, url, headers, @utf8.encode(wire)) {
    Ok(value) => value
    Err(issue) => return Err(Http(issue))
  }
  if response.status != 204 {
    return Err(HttpStatus(response.status))
  }
  if response.body.length() != 0 {
    return Err(InvalidResponse)
  }
  // A successful remote save may have occurred even if local authority/custody
  // changed during I/O. Do not return a current completion permission then.
  let (current_report, current_wire) = match
    self.review_projection(authorize_evidence_read, 65536) {
    Ok(value) => value
    Err(issue) => return Err(Review(issue))
  }
  if current_wire != wire ||
    @remote.remote_effect_checkpoint_report_identity(current_report) !=
    @remote.remote_effect_checkpoint_report_identity(report) {
    return Err(InvalidResponse)
  }
  Ok(())
}
