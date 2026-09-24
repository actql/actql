///|
/// The physical HTTPS adapter owns authentication and bounded request I/O.
/// This endpoint binds an authenticated Coordinator to one native Site and
/// delegates all dispatch transitions and output custody to the common
/// runtime and its durable journal.
struct NativeRemoteValuesSiteEndpoint {
  runtime : @runtime.NativeRemoteRuntime
  journal : @journal.Journal
  coordinator_authority : String
  site_key : String
  site_generation : Int
}

///|
pub(all) enum NativeRemoteValuesSiteEndpointIssue {
  InvalidConfiguration
  InvalidEnvelope
  ForeignDispatch
  Runtime(@runtime.NativeRemoteRuntimeIssue)
  Journal(@journal.NativeRemoteJournalIssue)
  Protocol(@remote.DispatchIssue)
}

///|
pub fn open_native_remote_values_site_endpoint(
  runtime : @runtime.NativeRemoteRuntime,
  journal : @journal.Journal,
  coordinator_authority : String,
  site_key : String,
  site_generation : Int,
) -> Result[NativeRemoteValuesSiteEndpoint, NativeRemoteValuesSiteEndpointIssue] {
  if coordinator_authority.is_empty() ||
    site_key.is_empty() ||
    site_generation < 0 {
    return Err(InvalidConfiguration)
  }
  Ok({ runtime, journal, coordinator_authority, site_key, site_generation, })
}

///|
fn NativeRemoteValuesSiteEndpoint::check_dispatch(
  self : NativeRemoteValuesSiteEndpoint,
  request : @remote.DispatchRequest,
  claimed_cid : String,
) -> Result[Unit, NativeRemoteValuesSiteEndpointIssue] {
  if @remote.dispatch_request_identity(request) != claimed_cid {
    return Err(ForeignDispatch)
  }
  let scope = @remote.dispatch_request_journal_key(request)
  if scope.length() != 7 ||
    scope[0] != self.coordinator_authority ||
    scope[1] != self.site_key ||
    scope[2] != self.site_generation.to_string() {
    return Err(ForeignDispatch)
  }
  Ok(())
}

///|
/// The common runtime accepts durably before Compute. Repeating the exact
/// envelope cannot start an already active occurrence a second time.
pub fn NativeRemoteValuesSiteEndpoint::dispatch_json(
  self : NativeRemoteValuesSiteEndpoint,
  envelope : String,
  claimed_cid : String,
) -> Result[String, NativeRemoteValuesSiteEndpointIssue] {
  let poll = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvelope)
  }
  let request = @remote.remote_poll_dispatch_request(poll)
  match self.check_dispatch(request, claimed_cid) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let binding = @remote.remote_poll_dispatch_input_binding(poll)
  match self.runtime.start(request, binding) {
    Ok(_) => ()
    Err(issue) => return Err(Runtime(issue))
  }
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  @remote.remote_dispatch_reply_json(
    @journal.recovered_site_dispatch_record(observed),
  ).map_err(issue => Protocol(issue))
}

///|
/// Query reads only retained Site evidence. It never creates a task or
/// retries Compute, including after a process restart or lost dispatch ACK.
pub fn NativeRemoteValuesSiteEndpoint::query_json(
  self : NativeRemoteValuesSiteEndpoint,
  envelope : String,
  claimed_cid : String,
) -> Result[String, NativeRemoteValuesSiteEndpointIssue] {
  let operation = match @remote.admit_remote_poll_operation_json(envelope) {
    Ok(value) if @remote.remote_poll_operation_is_query(value) => value
    _ => return Err(InvalidEnvelope)
  }
  let request = @remote.remote_poll_operation_request(operation)
  match self.check_dispatch(request, claimed_cid) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  @remote.remote_dispatch_status_json(
    @journal.recovered_site_dispatch_record(observed),
    @journal.recovered_site_dispatch_evidence(observed),
    @journal.recovered_site_dispatch_subject(observed),
    @journal.recovered_site_dispatch_measurement(observed),
  ).map_err(issue => Protocol(issue))
}
