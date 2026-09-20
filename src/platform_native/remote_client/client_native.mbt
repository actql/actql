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
/// Persist the exact Coordinator intent before the first physical send.
pub fn dispatch(
  journal : @journal.CoordinatorJournal,
  client : @http.Client,
  url : String,
  request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
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
    Ok(Some(@remote.Query(_))) | Ok(Some(@remote.Release(_))) =>
      Err(Protocol(@remote.InvalidDispatch))
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
        ) {
        Ok(value) => value
        Err(issue) => return Err(Protocol(issue))
      }
      (Some(record), body)
    }
    Err(@journal.StateCollision) => {
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
