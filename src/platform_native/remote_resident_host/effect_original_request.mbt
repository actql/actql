///|
/// Read the original transported request only from the live producer and its
/// saved original dispatch. A materials body without that context does not
/// synthesize another caller id, logical scope or Effect dispatch key.
pub fn ResidentEffectProducerExecuted::request_for_capture(
  self : ResidentEffectProducerExecuted,
  journal : @journal.Journal,
) -> @host.ClientRequestIdentity? {
  guard self.materials_for_capture(journal) is Some(materials) else {
    return None
  }
  match
    @host.client_effect_run_materials_request_for_dispatch(
      materials,
      self.executed.request,
    ) {
    Ok(Some(request)) => Some(request)
    _ => None
  }
}

///|
/// The computation must still possess its exact acquired input or receiver borrow. This
/// record is identity only; current Provider observe/approve/write authority
/// remains independently required by the existing credential/Effect Owners.
pub fn ResidentSourceCompute::request_for_effect_review(
  self : ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
) -> @host.ClientRequestIdentity? {
  guard self.resident_effect_inputs_current(inputs) &&
    self.effect_materials_for_capture() is Some(materials) else {
    return None
  }
  match self.effect_retained {
    Some(retained) =>
      match
        @host.client_effect_run_materials_request_for_dispatch(
          materials,
          retained.dispatch,
        ) {
        Ok(Some(request)) => Some(request)
        _ => None
      }
    None => materials.request
  }
}

///|
// Resolve original context through the existing producer journal before reading
// candidate consumer materials. A candidate wire cannot supply its own expected
// request; a lookup address grants neither input custody nor execution.
fn retained_effect_consumer_materials(
  journal : @journal.Journal,
  producer : @remote.DispatchRequest,
  consumer : @remote.DispatchRequest,
  body : String,
  admission : ResidentRunAdmission,
  limits : @host.ClientEffectComputationLimits,
) -> Result[@host.ClientEffectRunMaterials, ResidentRetainedExecutionIssue] {
  if @remote.dispatch_request_task_scope(producer).0 !=
    @remote.dispatch_request_task_scope(consumer).0 ||
    @remote.dispatch_request_journal_key(producer)[0] !=
    @remote.dispatch_request_journal_key(consumer)[0] ||
    @remote.dispatch_request_execution_scope(producer) !=
    @remote.dispatch_request_execution_scope(consumer) {
    return Err(Input(@output.InvalidBinding))
  }
  let attempt = match @remote.dispatch_request_attempt_identity(producer) {
    Ok(value) => value
    Err(issue) => return Err(Host(Protocol(issue)))
  }
  guard journal.dispatch_envelope(attempt) is Ok(Some(saved)) &&
    @remote.admit_remote_poll_dispatch_json(saved) is Ok(dispatch) &&
    @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) ==
    @remote.dispatch_request_identity(producer) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(original_wire) else {
    return Err(Host(EnvelopeMissing))
  }
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  let expected_request = match
    @host.client_effect_source_binding_request(binding, producer) {
    Ok(value) => value
    Err(issue) => return Err(EffectDispatch(issue))
  }
  let read = wire => {
    @host.admit_client_effect_run_materials(
      wire,
      @remote.dispatch_request_task_scope(producer).0,
      admission.expressions,
      admission.operations,
      admission.manifests,
      admission.limits,
      limits,
      expected_request~,
    ).map_err(issue => ResidentRetainedExecutionIssue::EffectMaterials(issue))
  }
  let original = match read(original_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Validate the saved envelope against the original checked Source issuer.
  // Matching a Root/request alone is not a producer dispatch binding.
  match @host.bind_client_effect_source_dispatch(original, producer, binding) {
    Ok(_) => ()
    Err(issue) => return Err(EffectDispatch(issue))
  }
  let retained = match
    @host.client_effect_run_materials_request_for_dispatch(original, producer) {
    Ok(value) => value
    Err(issue) => return Err(EffectMaterials(Request(issue)))
  }
  // The same complete wire already passed admission in this operation. Keep
  // its original checked owner; differing material still needs full admission.
  let target = if body == original_wire {
    original
  } else {
    match read(body) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  let selected = match
    @host.client_effect_run_materials_request_for_dispatch(target, consumer) {
    Ok(value) => value
    Err(issue) => return Err(EffectMaterials(Request(issue)))
  }
  if selected != retained {
    return Err(EffectMaterials(Request(IdentityMismatch)))
  }
  Ok(target)
}
