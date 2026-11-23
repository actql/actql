///|
// The fixed physical adapter already owns the original request. The consumed
// Entry carries its own original prepared call set; no late adapter callback
// or caller-supplied call-set alias is needed to register physical custody.
// Request equality is nominal, not matching wire bytes or a reported CID.
pub fn model_physical_call_for_request(
  entry : ModelCallEntry,
  request : ModelRequest,
  poll : () -> ModelPhysicalCallPoll,
  cancel : () -> Unit,
  cleanup : (Bool) -> Bool,
) -> ModelPhysicalCall? {
  guard entry.prepared.owner.state.requests.get(entry.slot) is Some(original) &&
    physical_equal(original.request, request) else {
    return None
  }
  // Preserve all existing consumed-entry, current phase, original attempt,
  // fixed asynchronous plan and open-reservation checks in the same Owner.
  model_physical_call(entry, entry.prepared, poll, cancel, cleanup)
}

///|
/// Register a new transport for a consumed Entry. Unlike the idempotent
/// observer above, a different transport may not adopt the existing Call.
pub fn register_model_physical_call_for_request(
  entry : ModelCallEntry,
  request : ModelRequest,
  poll : () -> ModelPhysicalCallPoll,
  cancel : () -> Unit,
  cleanup : (Bool) -> Bool,
) -> ModelPhysicalCall? {
  guard entry.progress.call is None else { return None }
  model_physical_call_for_request(entry, request, poll, cancel, cleanup)
}

///|
pub(all) enum ModelPhysicalDispatchReadIssue {
  Dispatch(ModelExecutionIssue)
  Raw(@publication_host.ClientModelRawCaptureIssue)
}

///|
// An outer Native Read drives the retained transport after the Core callback
// returns. Its check uses the same already-consumed Entry, Plan and Request.
// This borrows these originals without changing the Model execution phase.
fn model_physical_call_dispatch_entry(
  call : ModelPhysicalCall,
  request : ModelRequest,
  profile : @environment.ModelResponseProfile,
  raw : @publication_host.ClientModelRawCaptureRegistration,
) -> ModelCallEntry? {
  guard !call.cancel_requested &&
    call.terminal is None &&
    call.entry is Some(entry) &&
    call.original_binding is Some(binding) &&
    physical_equal(binding.entry, entry) &&
    entry.progress.phase is AwaitPhysicalResponse &&
    model_raw_capture_call_owned(call) else {
    return None
  }
  let owner = entry.prepared.owner
  let state = owner.state
  guard !state.stop_requested &&
    !@bounded.session_stopped(owner.session) &&
    entry.prepared.scope is Some(scope) &&
    @publication_host.client_model_raw_capture_matches(
      raw,
      entry.admission,
      scope,
    ) &&
    state.reservations.get(entry.slot) is Some(reservation) &&
    physical_equal(binding.reservation, reservation) &&
    state.physical_plans.get(entry.slot) is Some(plan) &&
    physical_equal(binding.plan, plan) &&
    physical_equal(plan.request, request) &&
    plan.response_profile is Some(actual_profile) &&
    physical_equal(actual_profile, profile) else {
    return None
  }
  Some(entry)
}

///|
/// Recheck current authority immediately before an already registered Native
/// transport sends from its original Read. The retained transport still owns
/// its one-shot start; this observation does not issue or consume another gate.
pub fn check_model_physical_call_dispatch_current(
  call : ModelPhysicalCall,
  request : ModelRequest,
  profile : @environment.ModelResponseProfile,
  raw : @publication_host.ClientModelRawCaptureRegistration,
) -> Result[Unit, ModelPhysicalDispatchReadIssue] {
  guard model_physical_call_dispatch_entry(call, request, profile, raw)
    is Some(entry) else {
    return Err(Dispatch(CallEntryRefused))
  }
  match @publication_host.check_client_infer_dispatch_current(entry.admission) {
    Ok(_) => ()
    Err(issue) => return Err(Dispatch(Authorization(issue)))
  }
  guard entry.prepared.owner.state.egress_admission is Some(admission) else {
    return Err(Dispatch(Egress(@publication_host.MissingObservation)))
  }
  match @publication_host.check_client_infer_egress_current(admission) {
    Ok(_) => ()
    Err(issue) => return Err(Dispatch(Egress(issue)))
  }
  if @publication_host.check_client_model_raw_capture_current(raw) is Err(issue) {
    return Err(Raw(issue))
  }
  guard model_physical_call_dispatch_entry(call, request, profile, raw)
    is Some(current) &&
    physical_equal(current, entry) else {
    return Err(Dispatch(CallEntryRefused))
  }
  Ok(())
}
