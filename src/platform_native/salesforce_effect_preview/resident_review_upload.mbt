///|
pub(all) enum NativeResidentEffectReviewUploadIssue {
  Review(NativeResidentEffectReviewIssue)
  Http(@http.NativeHttpIssue)
  HttpStatus(Int)
  InvalidResponse
}

///|
/// Send the exact confirmed original projection to the configured Cloud
/// artifact URL. The Client supplies its existing Site credential; the header
/// comes from the original typed report, never a caller-proposed identity.
/// A 204 confirms artifact save only, not report ACK, approval or release.
/// Failure/uncertainty leaves all existing custody live for explicit retry.
pub fn NativeResidentEffectReview::upload_review_projection(
  self : NativeResidentEffectReview,
  client : @http.Client,
  url : String,
  authorize_evidence_read : () -> Bool,
) -> Result[Unit, NativeResidentEffectReviewUploadIssue] {
  let (report, wire) = match
    self.review_projection(authorize_evidence_read, 65536) {
    Ok(value) => value
    Err(issue) => return Err(Review(issue))
  }
  let dispatch = @remote.remote_effect_checkpoint_report_dispatch(report)
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
