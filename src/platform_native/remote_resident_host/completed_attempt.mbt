///|
/// One caller around the original Runtime responsibility, not another ledger.
/// Keep this exact value on Pending; creating another value is not a retry.
pub struct ResidentCompletedAttempt {
  runtime : @runtime.NativeRemoteRuntime
  request : @remote.DispatchRequest
  binding : @remote.RemoteInputBinding
  result_definition_cid : String?
  root : String
  max_bytes : Int64
  current : () -> Bool
}

///|
pub(all) enum ResidentCompletedRestoration {
  ResidentCompletedReady(ResidentExecuted)
  ResidentCompletedPending(ResidentHostIssue)
  ResidentCompletedRefused(ResidentHostIssue)
}

///|
/// Admission of the saved envelope precedes native registry selection and I/O.
fn admit_resident_completed_envelope(
  admission : ResidentRunAdmission,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  attempt_identity : String,
  envelope : String,
  at : String,
) -> Result[
  (
    @remote.DispatchRequest,
    @remote.RemoteInputBinding,
    @host.ClientRunMaterials,
  ),
  ResidentHostIssue,
] {
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  guard @remote.dispatch_request_attempt_identity(request) ==
    Ok(attempt_identity) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Err(EnvelopeMissing)
  }
  match
    @resident.check_resident_dispatch_delegation(
      delegation, request, site_generation,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Refused(issue))
  }
  let materials = match admit_materials(admission, request, body, binding, at) {
    Ok(value) => value
    Err(issue) => return Err(Refused(issue))
  }
  if !(resident_source_dispatch_role(materials, request)
    is Ok(InternalSourceProducer)) {
    return Err(Refused(@resident.UnsupportedTask))
  }
  Ok((request, binding, materials))
}

///|
/// Select the saved start claimant for an original completed holder before
/// acquiring its runtime component. The caller must already hold the actual
/// exclusive slot. This does not release a holding or create another claim.
pub fn resident_completed_holder_claimant(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  attempt_identity : String,
  at : String,
) -> Result[String?, ResidentHostIssue] {
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  if @remote.dispatch_request_attempt_identity(request) != Ok(attempt_identity) {
    return Err(EnvelopeMissing)
  }
  let record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if @remote.dispatch_record_state_codes(record)[0] != 3 {
    return Ok(None)
  }
  match admit_resident_completed_envelope(
    admission, delegation, site_generation, attempt_identity, envelope, at,
  ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !(journal.cancellation_requested(request) is Ok(false)) {
    return Err(Refused(@resident.NotCurrent))
  }
  let saved = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_evidence(saved) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(saved) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(saved) is Some(measurement) &&
    @journal.recovered_site_dispatch_file_custody(saved) is Some(_) else {
    return Err(Runtime(@runtime.CompletedRestorationPending))
  }
  match @remote.restore_remote_runtime_completed_custody(
    record, evidence, subject, measurement,
  ) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  match journal.start_claimant(request) {
    Ok(Some(value)) => Ok(Some(value))
    Ok(None) => Err(Runtime(@runtime.CompletedRestorationPending))
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Rebuild the original checked producer from its saved envelope. The trusted
/// holder port must inspect its actual exclusive slot; stored generation alone
/// is not authority. Installation performs no Source I/O or executor entry.
pub fn prepare_resident_completed_attempt(
  journal : @journal.Journal,
  execution : ResidentExecution,
  admission : ResidentRunAdmission,
  delegation : @resident.ResidentSiteDelegation,
  attempt_identity : String,
  current_time : () -> String,
  exclusive_current : () -> Bool,
) -> Result[ResidentCompletedAttempt, ResidentExecutionFailure] {
  if !exclusive_current() {
    return Err(failed(Refused(@resident.NotCurrent)))
  }
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return Err(failed(EnvelopeMissing))
    Err(issue) => return Err(failed(Journal(issue)))
  }
  let (request, binding, materials) = match
    admit_resident_completed_envelope(
      admission,
      delegation,
      @site.site_generation(execution.site),
      attempt_identity,
      envelope,
      current_time(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(failed(issue))
  }
  guard execution.source is Some(source) &&
    source.retained_output_root is Some(root) else {
    return Err(failed(Source(UnsupportedSource)))
  }
  let current = () => {
    exclusive_current() &&
    @site.site_key(execution.site) == delegation.site_key &&
    @site.site_binding_current(
      execution.site,
      @site.site_generation(execution.site),
      delegation.runtime_bundle_cid,
    ) &&
    @resident.check_resident_dispatch_delegation(
      delegation,
      request,
      @site.site_generation(execution.site),
    )
    is Ok(_) &&
    @resident.check_resident_materials_current(materials, current_time())
    is Ok(_) &&
    journal.cancellation_requested(request) is Ok(false)
  }
  if !current() {
    return Err(failed(Refused(@resident.NotCurrent)))
  }
  let saved = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(failed(Journal(issue)))
  }
  guard @journal.recovered_site_dispatch_evidence(saved) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(saved) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(saved) is Some(measurement) &&
    @journal.recovered_site_dispatch_file_custody(saved) is Some(_) else {
    return Err(failed(Runtime(@runtime.CompletedRestorationPending)))
  }
  if @remote.restore_remote_runtime_completed_custody(
      @journal.recovered_site_dispatch_record(saved),
      evidence,
      subject,
      measurement,
    )
    is Err(issue) {
    return Err(failed(Protocol(issue)))
  }
  let (runtime, result_definition_cid) = match
    open_resident_attempt_runtime(
      journal,
      execution,
      materials,
      binding,
      request,
      current_time,
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    runtime,
    request,
    binding,
    result_definition_cid,
    root,
    max_bytes: execution.limits.output.max_retained_bytes,
    current,
  })
}

///|
/// Retry the original Runtime acquisition, never preparation or execution.
/// Pending retains the same physical cleanup/reservation responsibility.
pub fn ResidentCompletedAttempt::advance(
  self : ResidentCompletedAttempt,
) -> ResidentCompletedRestoration {
  match
    @output.restore_native_remote_standard_runtime_output(
      self.runtime,
      self.request,
      self.binding,
      self.root,
      self.max_bytes,
      self.current,
    ) {
    @runtime.CompletedRuntimeReady(completion) =>
      ResidentCompletedReady({
        runtime: self.runtime,
        completion,
        request: self.request,
        result_definition_cid: self.result_definition_cid,
      })
    @runtime.CompletedRuntimePending(issue) =>
      ResidentCompletedPending(Runtime(issue))
    @runtime.CompletedRuntimeRefused(issue) =>
      ResidentCompletedRefused(Runtime(issue))
  }
}

///|
/// Transfer only this existing cleanup responsibility to the caller. It must
/// retain Runtime on failure and must not prepare another restoration value.
pub fn ResidentCompletedAttempt::runtime(
  self : ResidentCompletedAttempt,
) -> @runtime.NativeRemoteRuntime {
  self.runtime
}
