///|
fn persist_unknown(
  journal : @journal.CoordinatorJournal,
  record : @remote.CoordinatorDispatchIntentRecord,
  primary : NativeRemoteClientIssue,
) -> NativeRemoteClientIssue {
  let transition = match @remote.prepare_coordinator_outcome_unknown(record) {
    Ok(value) => value
    Err(issue) => return Protocol(issue)
  }
  match journal.commit_transition(transition) {
    Ok(_) => primary
    Err(issue) => OutcomeUnknownPersistence(issue, primary)
  }
}

///|
fn exchange(
  journal : @journal.CoordinatorJournal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
  record : @remote.CoordinatorDispatchIntentRecord,
  kind : @remote.RemoteDispatchResponseKind,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  let body = match @remote.dispatch_request_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let physical = match client.post_json(url, body) {
    Ok(value) => value
    Err(issue) => return Err(persist_unknown(journal, record, Http(issue)))
  }
  if physical.status != 200 {
    return Err(persist_unknown(journal, record, HttpStatus(physical.status)))
  }
  let response_text = @utf8.decode(physical.body) catch {
    _ => return Err(persist_unknown(journal, record, InvalidUtf8))
  }
  let response = match
    @remote.admit_remote_dispatch_response_json(response_text, request, kind) {
    Ok(value) => value
    Err(issue) => return Err(persist_unknown(journal, record, Protocol(issue)))
  }
  let transition = match
    @remote.prepare_coordinator_response_observation(record, response) {
    Ok(value) => value
    Err(issue) => return Err(persist_unknown(journal, record, Protocol(issue)))
  }
  match
    journal.commit_transition(
      transition,
      evidence=@remote.remote_dispatch_response_evidence(response),
      subject=@remote.remote_dispatch_response_subject(response),
      measurement=@remote.remote_dispatch_response_measurement(response),
    ) {
    Ok(_) => Ok(response)
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Persist the exact Coordinator intent before the first physical send. The
/// Run owner's evaluated authorization is checked first: a deny, pending
/// Checkpoint or decision failure records no intent and sends nothing.
pub fn dispatch(
  journal : @journal.CoordinatorJournal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
  authorization : @authorization.RuntimeAction,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  if !remote_dispatch_authorized(authorization, request) {
    return Err(NotAuthorized)
  }
  let record = match journal.accept(request) {
    Ok((_, value)) => value
    Err(issue) => return Err(Journal(issue))
  }
  exchange(journal, client, url, request, record, @remote.DispatchReply)
}

///|
/// Query an existing intent. It never creates dispatch authority.
pub fn query(
  journal : @journal.CoordinatorJournal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  let record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  exchange(journal, client, url, request, record, @remote.StatusReply)
}

///|
/// Request cancellation for an existing intent. A successful HTTP response is
/// only a Site observation; it is not native-stop evidence by itself.
pub fn cancel(
  journal : @journal.CoordinatorJournal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  let record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  exchange(journal, client, url, request, record, @remote.DispatchReply)
}

///|
/// Poll an outbound control endpoint. Dispatch delivery and status queries
/// remain distinct operations after canonical admission.
pub fn poll_operation(
  client : @http.Client,
  url : String,
) -> Result[@remote.RemotePollOperation?, NativeRemoteClientIssue] {
  let physical = match client.post_json(url, b"{}") {
    Ok(value) => value
    Err(issue) => return Err(Http(issue))
  }
  if physical.status == 204 {
    if physical.body.length() == 0 {
      return Ok(None)
    }
    return Err(Protocol(@remote.InvalidDispatch))
  }
  if physical.status != 200 {
    return Err(HttpStatus(physical.status))
  }
  let response_text = @utf8.decode(physical.body) catch {
    _ => return Err(InvalidUtf8)
  }
  match @remote.admit_remote_poll_operation_json(response_text) {
    Ok(value) => Ok(Some(value))
    Err(issue) => Err(Protocol(issue))
  }
}

///|
/// Compatibility helper for dispatch-only consumers. A query cannot be
/// mistaken for executable work.
pub fn poll(
  client : @http.Client,
  url : String,
) -> Result[@remote.DispatchRequest?, NativeRemoteClientIssue] {
  match poll_operation(client, url) {
    Ok(None) => Ok(None)
    Ok(Some(@remote.Dispatch(dispatch))) =>
      Ok(Some(@remote.remote_poll_dispatch_request(dispatch)))
    Ok(Some(@remote.Plan(_)))
    | Ok(Some(@remote.Output(_)))
    | Ok(Some(@remote.Query(_)))
    | Ok(Some(@remote.Release(_))) => Err(Protocol(@remote.InvalidDispatch))
    Err(issue) => Err(issue)
  }
}

///|
/// Durably accept a polled dispatch before acknowledging it to the
/// Coordinator. Repeating this operation reconciles the same Site record.
pub fn acknowledge_acceptance(
  journal : @journal.Journal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
) -> Result[@remote.DispatchRecord, NativeRemoteClientIssue] {
  let record = match journal.accept(request) {
    Ok((_, value)) => value
    Err(issue) => return Err(Journal(issue))
  }
  let body = match @remote.remote_dispatch_reply_json(record) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match client.post_json(url, body) {
    Ok(value) if value.status == 200 => Ok(record)
    Ok(value) => Err(HttpStatus(value.status))
    Err(issue) => Err(Http(issue))
  }
}

///|
/// Reply to an outbound status query from an existing durable Site record.
/// A query never admits a new dispatch or starts physical execution.
pub fn acknowledge_status(
  journal : @journal.Journal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
) -> Result[@remote.DispatchRecord?, NativeRemoteClientIssue] {
  let found = journal.observation(request)
  let (record, body) = match found {
    Ok(observation) => {
      let record = @journal.recovered_site_dispatch_record(observation)
      let body = match
        @remote.remote_dispatch_status_json(
          record,
          @journal.recovered_site_dispatch_evidence(observation),
          @journal.recovered_site_dispatch_subject(observation),
          @journal.recovered_site_dispatch_measurement(observation),
          source_observation=@journal.recovered_site_dispatch_source_observation(
            observation,
          ),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Protocol(issue))
      }
      (Some(record), body)
    }
    Err(@journal.MissingDispatch) => {
      let body = match @remote.remote_poll_not_seen_json(request) {
        Ok(value) => value
        Err(issue) => return Err(Protocol(issue))
      }
      (None, body)
    }
    Err(issue) => return Err(Journal(issue))
  }
  match client.post_json(url, @utf8.encode(body)) {
    Ok(value) if value.status == 200 => Ok(record)
    Ok(value) => Err(HttpStatus(value.status))
    Err(issue) => Err(Http(issue))
  }
}

///|
/// Post one canonical retained-output result. The physical payload and
/// Transfer records are already durable. Only a checked, report-bound
/// response acknowledges this observation; a bare HTTP 200 is not an ACK.
pub fn acknowledge_output_result(
  client : @http.Client,
  url : String,
  result : @remote.RemoteOutputResult,
) -> Result[Unit, NativeRemoteClientIssue] {
  let body = match @remote.remote_output_result_json(result) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let response = match client.post_json(url, body) {
    Ok(value) => value
    Err(issue) => return Err(Http(issue))
  }
  let text = @utf8.decode(response.body) catch { _ => return Err(InvalidUtf8) }
  match @remote.admit_remote_output_report_reply_json(text, result) {
    Ok(@remote.RemoteOutputReportReply::Accepted) if response.status == 200 =>
      Ok(())
    Ok(@remote.RemoteOutputReportReply::Refused(reason)) if response.status ==
      409 => Err(OutputReportRefused(reason))
    Ok(@remote.RemoteOutputReportReply::Retry(_)) =>
      Err(Protocol(@remote.InvalidDispatch))
    _ if response.status != 200 => Err(HttpStatus(response.status))
    _ => Err(Protocol(@remote.InvalidDispatch))
  }
}

///|
/// Replay the exact saved report. The journal independently tracks physical
/// cleanup and checked acknowledgement; no runtime or Transfer is reopened.
pub fn acknowledge_retained_output_report(
  journal : @journal.Journal,
  client : @http.Client,
  url : String,
  key : String,
  checkpoint? : (String) -> Unit = fn(_) {  },
) -> Result[Unit, NativeRemoteClientIssue] {
  let (custody, reply) = match journal.output_report(key) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match reply {
    Some(@remote.RemoteOutputReportReply::Accepted) => return Ok(())
    Some(@remote.RemoteOutputReportReply::Refused(reason)) =>
      return Err(OutputReportRefused(reason))
    Some(@remote.RemoteOutputReportReply::Retry(_)) => ()
    None => ()
  }
  // This validates the current Site binding even after physical release.
  // Reusing the existing durable original is idempotent, not new execution.
  match journal.retain_output_report(custody) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let result = @remote.remote_output_report_custody_result(custody)
  let body = match @remote.remote_output_result_json(result) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let response = match client.post_json(url, @utf8.encode(body)) {
    Ok(value) => value
    Err(issue) => return Err(Http(issue))
  }
  let text = @utf8.decode(response.body) catch { _ => return Err(InvalidUtf8) }
  let admitted = match
    @remote.admit_remote_output_report_reply_json(text, result) {
    Ok(value) => value
    Err(issue) =>
      return if response.status == 200 {
        Err(Protocol(issue))
      } else {
        Err(HttpStatus(response.status))
      }
  }
  if admitted is @remote.RemoteOutputReportReply::Accepted &&
    response.status != 200 {
    return Err(HttpStatus(response.status))
  }
  if admitted is @remote.RemoteOutputReportReply::Refused(_) &&
    response.status != 409 {
    return Err(HttpStatus(response.status))
  }
  checkpoint("before-ack-save")
  match journal.record_output_report_reply(key, text) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  checkpoint("after-ack-save")
  match admitted {
    @remote.RemoteOutputReportReply::Accepted => Ok(())
    @remote.RemoteOutputReportReply::Refused(reason) =>
      Err(OutputReportRefused(reason))
    @remote.RemoteOutputReportReply::Retry(_) =>
      Err(Protocol(@remote.InvalidDispatch))
  }
}

///|
/// Post one side-effect-free output plan derived from immutable Site facts.
pub fn acknowledge_output_plan(
  client : @http.Client,
  url : String,
  plan : @remote.RemoteOutputPlan,
) -> Result[Unit, NativeRemoteClientIssue] {
  let body = match @remote.remote_output_plan_json(plan) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match client.post_json(url, body) {
    Ok(value) if value.status == 200 => Ok(())
    Ok(value) => Err(HttpStatus(value.status))
    Err(issue) => Err(Http(issue))
  }
}
