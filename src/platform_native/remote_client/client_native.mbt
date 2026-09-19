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
