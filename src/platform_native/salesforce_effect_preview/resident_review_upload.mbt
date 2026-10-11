///|
pub(all) enum NativeResidentEffectReviewUploadIssue {
  Review(NativeResidentEffectReviewIssue)
  OriginalReview(@resident.ResidentEffectOriginalReviewIssue)
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
  upload_original_review_projection(
    self.journal,
    client,
    report_url,
    url,
    () => {
      match self.review_projection(authorize_evidence_read, 65536) {
        Ok(value) => Ok(value)
        Err(issue) => Err(Review(issue))
      }
    },
    () => {
      if !authorize_evidence_read() {
        Err(Review(Retention(EvidenceDenied)))
      } else if self.closed || self.retiring || !self.current() {
        Err(Review(Unavailable))
      } else {
        Ok(())
      }
    },
  )
}

///|
/// Resume only the original confirmed report/projection through a genuine
/// consumer context and its authenticated Store. This does not reconstruct a
/// physical Review, create a Preview, grant approval or execute an Effect.
/// Disclosure authority must come from the same trusted Host policy entry as
/// the live Review path; Store authority and Run admission are not permission.
pub fn upload_native_resident_original_review_projection(
  context : @resident.ResidentEffectReviewInputContext,
  journal : @journal.Journal,
  store : @store.Store,
  authority : String,
  crypto : @signature.Library,
  key : Bytes,
  limits : @checkpoint.WireLimits,
  client : @http.Client,
  report_url : String,
  url : String,
  authorize_evidence_read : () -> Bool,
) -> Result[Unit, NativeResidentEffectReviewUploadIssue] {
  upload_original_review_projection(
    journal,
    client,
    report_url,
    url,
    () => {
      match
        context.read_original_review_projection(
          journal, store, authority, crypto, key, limits, authorize_evidence_read,
        ) {
        Ok(value) => Ok(value)
        Err(issue) => Err(OriginalReview(issue))
      }
    },
    () => {
      if !authorize_evidence_read() {
        Err(OriginalReview(EvidenceDenied))
      } else if context.facts(journal) is None {
        Err(OriginalReview(Unavailable))
      } else {
        Ok(())
      }
    },
  )
}

///|
/// Both nominal entry points use the existing report ACK and HTTP Owners.
/// The private reader supplies independently confirmed original custody before
/// ACK, after ACK and after artifact save. No public caller may supply wire.
fn upload_original_review_projection(
  journal : @journal.Journal,
  client : @http.Client,
  report_url : String,
  url : String,
  read : () -> Result[
    (@remote.RemoteEffectCheckpointReport, String),
    NativeResidentEffectReviewUploadIssue,
  ],
  fence : () -> Result[Unit, NativeResidentEffectReviewUploadIssue],
) -> Result[Unit, NativeResidentEffectReviewUploadIssue] {
  let (report, wire) = match read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Preserve the existing projection transport limit even when the original
  // continuation permits a larger bound for its captured input evidence.
  if @utf8.encode(wire).length() > 65536 {
    return Err(InvalidResponse)
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
  match confirm_original_review_report(journal, report, limits, false) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match fence() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    @client.acknowledge_retained_effect_checkpoint(
      journal, client, report_url, dispatch, limits,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Report(issue))
  }
  // The remote ACK may be durable even if local disclosure authority changed
  // during I/O. Preserve that fact, but do not send the review under stale
  // authority or replace its original report with a newer projection.
  let (confirmed_report, confirmed_wire) = match read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if confirmed_wire != wire ||
    @remote.remote_effect_checkpoint_report_identity(confirmed_report) !=
    @remote.remote_effect_checkpoint_report_identity(report) {
    return Err(InvalidResponse)
  }
  match confirm_original_review_report(journal, report, limits, true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let headers : Array[@http.NativeHttpHeader] = [
    { name: "content-type", value: "application/json", },
    {
      name: "actql-dispatch-cid",
      value: @remote.dispatch_request_identity(dispatch),
    },
  ]
  let body = @utf8.encode(wire)
  // Prepare the bounded body before the final current disclosure fence.
  // Journal confirmation is evidence, never a substitute for current permission.
  match fence() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let response = match client.request(Post, url, headers, body) {
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
  let (current_report, current_wire) = match read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if current_wire != wire ||
    @remote.remote_effect_checkpoint_report_identity(current_report) !=
    @remote.remote_effect_checkpoint_report_identity(report) {
    return Err(InvalidResponse)
  }
  match confirm_original_review_report(journal, report, limits, true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  fence()
}

///|
/// The ACK Owner reads the journal, whereas the review Owner reads the paired
/// Store. Bind both originals before any send and recheck the durable Accepted
/// receipt after I/O; a valid different report for the dispatch is insufficient.
fn NativeResidentEffectReview::confirm_original_review_report(
  self : NativeResidentEffectReview,
  original : @remote.RemoteEffectCheckpointReport,
  limits : @checkpoint.WireLimits,
  require_accepted : Bool,
) -> Result[Unit, NativeResidentEffectReviewUploadIssue] {
  confirm_original_review_report(
    self.journal,
    original,
    limits,
    require_accepted,
  )
}

///|
fn confirm_original_review_report(
  journal : @journal.Journal,
  original : @remote.RemoteEffectCheckpointReport,
  limits : @checkpoint.WireLimits,
  require_accepted : Bool,
) -> Result[Unit, NativeResidentEffectReviewUploadIssue] {
  let dispatch = @remote.remote_effect_checkpoint_report_dispatch(original)
  let (saved, reply) = match
    journal.effect_checkpoint_report(dispatch, limits) {
    Ok(value) => value
    Err(issue) => return Err(Report(@client.Journal(issue)))
  }
  if @remote.remote_effect_checkpoint_report_identity(saved) !=
    @remote.remote_effect_checkpoint_report_identity(original) ||
    @remote.remote_effect_checkpoint_report_json(saved) !=
    @remote.remote_effect_checkpoint_report_json(original) {
    return Err(InvalidResponse)
  }
  if require_accepted &&
    !(reply is Some(@remote.RemoteEffectCheckpointReply::Accepted)) {
    return Err(InvalidResponse)
  }
  Ok(())
}
