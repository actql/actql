///|
fn resident_saved_task_materials(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
) -> Result[
  (@host.ClientRunMaterials, @remote.RemoteInputBinding),
  ResidentHostIssue,
] {
  guard @remote.dispatch_request_attempt_identity(request) is Ok(attempt) else {
    return Err(EnvelopeMissing)
  }
  let body = match journal.dispatch_envelope(attempt) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  guard @remote.admit_remote_poll_dispatch_json(body) is Ok(dispatch) &&
    @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) ==
    @remote.dispatch_request_identity(request) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) else {
    return Err(EnvelopeMissing)
  }
  let rebuilt = match rebuild_materials(admission, request, materials) {
    Ok(value) => value
    Err(issue) => return Err(Refused(issue))
  }
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err(Refused(@resident.ForeignSource))
  }
  Ok((rebuilt, binding))
}

///|
/// Recover only the original incoming cleanup responsibility. No reader is
/// acquired, revived, or treated as current use authority. The actual holder
/// slot/Site owner must authorize each cleanup attempt, including after expiry.
pub fn prepare_resident_saved_input_cleanup(
  journal : @journal.Journal,
  transfer_journal : @transfer_journal.Journal,
  retained_root : @filesystem.Root?,
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
  max_referenced_bytes : Int64,
  cleanup_current : () -> Bool,
  recorded_source? : @publication.RecordedRunPublication? = None,
) -> Result[(() -> Bool)?, ResidentHostIssue] {
  if recorded_source is Some(original) {
    // The checked Source root has no incoming held input. This is only a
    // role projection; output files, process stop and bundle cleanup remain
    // independent obligations of the caller's existing physical owners.
    return resident_saved_recorded_source_cleanup(
      journal, admission, request, original,
    ).map(_ => None)
  }
  let (materials, binding) = match
    resident_saved_task_materials(journal, admission, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if resident_saved_values_binding(materials, request, binding) {
    return Ok(None)
  }
  guard resident_linear_task_index(materials, request) is Some(task) else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  if task == 0 {
    guard @host.prepare_client_task_input_binding(materials.prepared, 0)
      is Ok(expected) &&
      @remote.remote_input_binding_body(expected) ==
      @remote.remote_input_binding_body(binding) else {
      return Err(Refused(@resident.ForeignSource))
    }
    return Ok(None)
  }
  guard retained_root is Some(root) else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  let route = match
    resident_retained_task_route(
      materials, request, binding, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let producer = @host.client_retained_task_route_producer_dispatch(route)
  let observation = match journal.observation(producer) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_evidence(observation) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(observation) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(observation)
    is Some(measurement) else {
    return Err(Runtime(@runtime.CompletedRestorationPending))
  }
  let consumer_record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let cleanup = match
    @host.prepare_client_retained_input_cleanup_for_route(
      route,
      @journal.recovered_site_dispatch_record(observation),
      evidence,
      subject,
      measurement,
      consumer_record,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.ForeignSource))
  }
  let retry = match
    prepare_resident_retained_input_cleanup_retry(
      cleanup,
      transfer_journal,
      root,
      cleanup_current,
      allow_unborrowed=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.NotCurrent))
  }
  Ok(Some(() => retry() is Ok(_)))
}

///|
/// Historical role projection for exact component custody. This does not
/// authorize execution and deliberately does not require unexpired use grants.
pub fn resident_holder_process_hold_identity(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  attempt_identity : String,
  claimant : String,
  recorded_source? : @publication.RecordedRunPublication? = None,
) -> Result[String, ResidentHostIssue] {
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  guard @remote.admit_remote_poll_dispatch_json(envelope) is Ok(dispatch) else {
    return Err(EnvelopeMissing)
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  if @remote.dispatch_request_attempt_identity(request) != Ok(attempt_identity) {
    return Err(EnvelopeMissing)
  }
  if recorded_source is Some(original) {
    match
      resident_saved_recorded_source_cleanup(
        journal, admission, request, original,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let original_claim = match journal.start_claimant(request) {
      Ok(Some(value)) => value
      _ => return Err(Refused(@resident.NotCurrent))
    }
    if claimant == "" || original_claim != claimant {
      return Err(Refused(@resident.NotCurrent))
    }
    return Ok("runtime-process:resident-holder:" + claimant)
  }
  let (materials, binding) = match
    resident_saved_task_materials(journal, admission, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if resident_saved_values_binding(materials, request, binding) {
    return Ok("runtime-process:resident-holder:" + claimant)
  }
  guard resident_linear_task_index(materials, request) is Some(task) else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  if task == 0 {
    guard @host.prepare_client_task_input_binding(materials.prepared, 0)
      is Ok(expected) &&
      @remote.remote_input_binding_body(expected) ==
      @remote.remote_input_binding_body(binding) else {
      return Err(Refused(@resident.ForeignSource))
    }
    Ok("runtime-process:resident-holder:" + claimant)
  } else {
    match
      resident_retained_task_route(
        materials, request, binding, 9223372036854775807L,
      ) {
      Ok(_) => Ok("consumer:" + @remote.dispatch_request_identity(request))
      Err(issue) => Err(issue)
    }
  }
}

///|
/// Admit only the saved original Source-root cleanup role. A failure never
/// falls back to current executable materials or another authority.
fn resident_saved_recorded_source_cleanup(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
  recorded : @publication.RecordedRunPublication,
) -> Result[Unit, ResidentHostIssue] {
  guard @remote.dispatch_request_attempt_identity(request) is Ok(attempt) else {
    return Err(EnvelopeMissing)
  }
  let wire = match journal.dispatch_envelope(attempt) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  guard @remote.admit_remote_poll_dispatch_json(wire) is Ok(dispatch) &&
    @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) ==
    @remote.dispatch_request_identity(request) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) &&
    admission.source is Some((source_ref, source_contract)) else {
    return Err(EnvelopeMissing)
  }
  let (run, _) = @remote.dispatch_request_task_scope(request)
  let graph = match
    @host.admit_recorded_client_source_cleanup_graph(
      materials,
      run,
      recorded,
      admission.expressions,
      admission.operations,
      admission.limits,
      source_ref,
      source_contract,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.ForeignSource))
  }
  if !@host.recorded_client_source_cleanup_matches_producer(
      graph,
      request,
      @remote.remote_poll_dispatch_input_binding(dispatch),
      source_ref,
      source_contract,
    ) {
    return Err(Refused(@resident.ForeignSource))
  }
  Ok(())
}

///|
fn resident_saved_values_binding(
  materials : @host.ClientRunMaterials,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
) -> Bool {
  guard materials.compilation is @host.Values(compilation) &&
    @host.bind_source_free_client_values_run(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
    )
    is Ok(checked) else {
    return false
  }
  @remote.remote_input_binding_body(binding) == "{}" &&
  @remote.remote_input_binding_matches_dispatch(binding, request) &&
  @remote.dispatch_request_task_scope(request) ==
  (
    @host.client_values_run_binding_definition_cid(checked),
    @host.client_values_run_binding_task_key(checked),
  )
}
