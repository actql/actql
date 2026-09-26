///|
/// The physical HTTPS adapter owns authentication and bounded request I/O.
/// This endpoint binds an authenticated Coordinator to one native Site and
/// delegates all dispatch transitions and output custody to the common
/// runtime and its durable journal.
struct NativeRemoteValuesSiteEndpoint {
  runtime : @runtime.NativeRemoteRuntime
  journal : @journal.Journal
  run_definition_cid : String
  task_key : String
  result_definition_cid : String
  coordinator_authority : String
  site_key : String
  site_generation : Int
}

///|
pub(all) enum NativeRemoteValuesSiteEndpointIssue {
  InvalidConfiguration
  InvalidEnvelope
  ForeignDispatch
  InvalidOutput
  OutputPlan(@output.NativeRemoteObservedOutputPlanIssue)
  OutputSource(@output.NativeRemoteStandardSiteComponentIssue)
  Transfer(@transfer.RemoteTransferIssue)
  Runtime(@runtime.NativeRemoteRuntimeIssue)
  Journal(@journal.NativeRemoteJournalIssue)
  Protocol(@remote.DispatchIssue)
}

///|
pub fn open_native_remote_values_site_endpoint(
  runtime : @runtime.NativeRemoteRuntime,
  journal : @journal.Journal,
  executor : NativeRemoteValuesTaskExecutor,
  coordinator_authority : String,
  site_key : String,
  site_generation : Int,
) -> Result[NativeRemoteValuesSiteEndpoint, NativeRemoteValuesSiteEndpointIssue] {
  if coordinator_authority.is_empty() ||
    site_key.is_empty() ||
    site_generation < 0 {
    return Err(InvalidConfiguration)
  }
  Ok({
    runtime,
    journal,
    run_definition_cid: executor.run_definition_cid,
    task_key: executor.task_key,
    result_definition_cid: executor.result_definition_cid,
    coordinator_authority,
    site_key,
    site_generation,
  })
}

///|
pub fn NativeRemoteValuesSiteEndpoint::route(
  self : NativeRemoteValuesSiteEndpoint,
) -> (String, Int) {
  (self.site_key, self.site_generation)
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
    scope[2] != self.site_generation.to_string() ||
    @remote.dispatch_request_task_scope(request) !=
    (self.run_definition_cid, self.task_key) {
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

///|
/// Derive publication and Transfer requests from the exact retained output.
/// The checked executor fixes the Run, task and Result Definition; the poll
/// supplies a Coordinator-issued output intent. Planning opens no payload
/// writer or Transfer reader and never repeats Compute.
pub fn NativeRemoteValuesSiteEndpoint::output_plan_json(
  self : NativeRemoteValuesSiteEndpoint,
  envelope : String,
  claimed_cid : String,
) -> Result[String, NativeRemoteValuesSiteEndpointIssue] {
  let poll = match @remote.admit_remote_poll_output_plan_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvelope)
  }
  let request = @remote.remote_poll_output_request(poll)
  match self.check_dispatch(request, claimed_cid) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let intent = @remote.remote_poll_output_intent(poll)
  let selected = @remote.remote_output_intent_projection(intent)
  if selected.result_definition_cid != self.result_definition_cid ||
    selected.coordinator_authority != self.coordinator_authority ||
    !@remote.remote_output_intent_matches_dispatch(intent, request) {
    return Err(InvalidOutput)
  }
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let record = @journal.recovered_site_dispatch_record(observed)
  let completion = match self.runtime.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  if !@remote.dispatch_record_matches_request(record, request) ||
    @remote.dispatch_record_revision(record) != completion.revision {
    return Err(InvalidOutput)
  }
  guard @journal.recovered_site_dispatch_subject(observed) is Some(subject) else {
    return Err(InvalidOutput)
  }
  if !@remote.remote_managed_output_subject_matches_dispatch(subject, request) ||
    @remote.remote_managed_output_subject_cid(subject) != completion.subject_cid {
    return Err(InvalidOutput)
  }
  let subject_fields = @remote.remote_managed_output_subject_projection(subject)
  if subject_fields.length() < 2 {
    return Err(InvalidOutput)
  }
  let facts = match
    self.runtime.inspect_output_facts(request, subject_fields[1]) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  let output_intent : @output.NativeRemoteObservedOutputIntent = {
    store_authority_cid: selected.store_authority_cid,
    publication_attempt_cid: selected.publication_attempt_cid,
    result_definition_cid: selected.result_definition_cid,
    ordering_evidence_cid: selected.ordering_evidence_cid,
    coordinator_authority: selected.coordinator_authority,
    transfer_attempt: selected.transfer_attempt,
    transfer_route: selected.transfer_route,
    destination_site_key: selected.destination_site_key,
    destination_site_generation: selected.destination_site_generation,
    transfer_max_bytes: selected.transfer_max_bytes,
    transfer_expires_unix_ms: selected.transfer_expires_unix_ms,
    source_grant_cid: selected.source_grant_cid,
    destination_grant_cid: selected.destination_grant_cid,
    route_capability_cid: selected.route_capability_cid,
  }
  let physical = match
    @output.prepare_native_remote_observed_output_plan(
      self.site_key,
      self.site_generation,
      facts,
      output_intent,
    ) {
    Ok(value) => value
    Err(issue) => return Err(OutputPlan(issue))
  }
  let plan = match
    @remote.prepare_remote_output_plan(
      poll,
      subject,
      physical.payload,
      physical.transfer,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  @remote.remote_output_plan_json(plan).map_err(issue => Protocol(issue))
}

///|
/// Open the exact retained output after the same checked plan admission used
/// by the HTTPS control route. The caller owns the reader's physical stop.
pub fn NativeRemoteValuesSiteEndpoint::open_output_manifest_reader(
  self : NativeRemoteValuesSiteEndpoint,
  envelope : String,
  claimed_cid : String,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputManifestReader,
  NativeRemoteValuesSiteEndpointIssue,
] {
  match self.output_plan_json(envelope, claimed_cid) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let poll = match @remote.admit_remote_poll_output_plan_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvelope)
  }
  let request = @remote.remote_poll_output_request(poll)
  let completion = match self.runtime.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  @output.open_native_remote_observed_output_manifest_reader(
    self.runtime,
    self.journal,
    request,
    completion,
    max_chunk_bytes,
  ).map_err(issue => OutputSource(issue))
}

///|
/// Recheck the exact Coordinator output intent and observed Site subject
/// before opening a durable direct Transfer. The destination origin is a
/// physical Site setting, not a URL accepted from the poll envelope.
pub fn NativeRemoteValuesSiteEndpoint::send_output_direct(
  self : NativeRemoteValuesSiteEndpoint,
  client : @http.Client,
  transfer_journal : @transfer_journal.Journal,
  destination_origin : String,
  envelope : String,
  claimed_cid : String,
  max_chunk_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteValuesSiteEndpointIssue] {
  let plan_wire = match self.output_plan_json(envelope, claimed_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let poll = match @remote.admit_remote_poll_output_plan_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvelope)
  }
  let request = @remote.remote_poll_output_request(poll)
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_subject(observed) is Some(subject) else {
    return Err(InvalidOutput)
  }
  let plan = match
    @remote.admit_remote_output_plan_json(
      plan_wire, poll, subject, max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let completion = match self.runtime.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  @output.send_native_remote_observed_output_direct(
    self.runtime,
    self.journal,
    client,
    transfer_journal,
    destination_origin,
    request,
    completion,
    @remote.remote_output_plan_transfer_request(plan),
    max_chunk_bytes,
  ).map_err(issue => OutputSource(issue))
}

///|
/// Return only the common Transfer reply for the exact request selected by
/// the checked Output Plan. A reply does not publish the Named Result.
pub fn NativeRemoteValuesSiteEndpoint::send_output_direct_json(
  self : NativeRemoteValuesSiteEndpoint,
  client : @http.Client,
  transfer_journal : @transfer_journal.Journal,
  destination_origin : String,
  envelope : String,
  claimed_cid : String,
  max_chunk_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[String, NativeRemoteValuesSiteEndpointIssue] {
  let record = match
    self.send_output_direct(
      client, transfer_journal, destination_origin, envelope, claimed_cid, max_chunk_bytes,
      max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @transfer.remote_transfer_reply_json(record).map_err(issue => Transfer(issue))
}

///|
/// The synchronous Values endpoint delegates stop and resource release to the
/// existing runtime. Unconfirmed cleanup keeps its owner; this operation never
/// starts a missing dispatch or changes an unknown execution into success.
fn NativeRemoteValuesSiteEndpoint::settle_control(
  self : NativeRemoteValuesSiteEndpoint,
  body : String,
  claimed_cid : String,
) -> Result[@remote.DispatchRequest, NativeRemoteValuesSiteEndpointIssue] {
  let request = match @remote.admit_dispatch_request_json(body, claimed_cid) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvelope)
  }
  match self.check_dispatch(request, claimed_cid) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.journal.observation(request) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match self.runtime.cleanup(request) {
    Ok(_) => ()
    Err(issue) => return Err(Runtime(issue))
  }
  match self.runtime.release(request) {
    Ok(_) => ()
    Err(issue) => return Err(Runtime(issue))
  }
  Ok(request)
}

///|
pub fn NativeRemoteValuesSiteEndpoint::cancel_json(
  self : NativeRemoteValuesSiteEndpoint,
  body : String,
  claimed_cid : String,
) -> Result[String, NativeRemoteValuesSiteEndpointIssue] {
  let request = match self.settle_control(body, claimed_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
pub fn NativeRemoteValuesSiteEndpoint::release_json(
  self : NativeRemoteValuesSiteEndpoint,
  body : String,
  claimed_cid : String,
) -> Result[String, NativeRemoteValuesSiteEndpointIssue] {
  let request = match self.settle_control(body, claimed_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let query = match @remote.remote_poll_query_json(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  self.query_json(query, claimed_cid)
}
