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
/// The consumer must still possess its current exact receiver borrow. This
/// record is identity only; current Provider observe/approve/write authority
/// remains independently required by the existing credential/Effect Owners.
pub fn ResidentSourceCompute::request_for_effect_review(
  self : ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
) -> @host.ClientRequestIdentity? {
  guard self.resident_effect_inputs_current(inputs) &&
    self.effect_retained is Some(retained) &&
    self.effect_materials_for_capture() is Some(materials) else {
    return None
  }
  match
    @host.client_effect_run_materials_request_for_dispatch(
      materials,
      retained.dispatch,
    ) {
    Ok(Some(request)) => Some(request)
    _ => None
  }
}

///|
fn retained_effect_consumer_original_request(
  journal : @journal.Journal,
  producer : @remote.DispatchRequest,
  consumer : @remote.DispatchRequest,
  body : String,
  admission : ResidentRunAdmission,
  limits : @host.ClientEffectComputationLimits,
) -> Result[Unit, ResidentRetainedExecutionIssue] {
  let read = wire => {
    @host.admit_client_effect_run_materials(
      wire,
      @remote.dispatch_request_task_scope(producer).0,
      admission.expressions,
      admission.operations,
      admission.manifests,
      admission.limits,
      limits,
    ).map_err(issue => ResidentRetainedExecutionIssue::EffectMaterials(issue))
  }
  let target = match read(body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let selected = match
    @host.client_effect_run_materials_request_for_dispatch(target, consumer) {
    Ok(value) => value
    Err(issue) => return Err(EffectMaterials(Request(issue)))
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
  let original = match read(original_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let retained = match
    @host.client_effect_run_materials_request_for_dispatch(original, producer) {
    Ok(value) => value
    Err(issue) => return Err(EffectMaterials(Request(issue)))
  }
  if selected != retained {
    return Err(EffectMaterials(Request(IdentityMismatch)))
  }
  Ok(())
}
