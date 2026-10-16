///|
pub enum ModelPhysicalEvent {
  BeforeInvoke
  InvokeStarted
  InvokeReturned
  InvokeFailed
  InvokeCancelled
}

///|
/// A diagnostic fact at the named boundary, not a dispatch permit, saved
/// response, usage receipt, or semantic completion. No payload is exposed.
/// BeforeInvoke explicitly precedes the final current check and is unsent.
/// Started means the invocation entry was crossed, not provider delivery.
pub struct ModelPhysicalObservation {
  slot : Int
  attempt_cid : String
  event : ModelPhysicalEvent
}

///|
/// Bind the installed Host's metadata-only observer to this exact live owner.
/// Delivery is outside the execution boundary; this hook only copies facts
/// It cannot replace admission or enter_call. BeforeInvoke is delivered before
/// the final gate; start/return facts are delivered after physical invocation.
/// Their delivery timestamps cannot measure a synchronous invocation interval.
pub fn bind_prepared_model_observation(
  value : ModelPreparedCallSet,
  observe : (ModelPhysicalObservation) -> Unit,
) -> Bool {
  let state = value.owner.state
  if check_model_original_resources_mutable(state) is Err(_) {
    return false
  }
  if !prepared_model_current(value) ||
    !(state.progress.phase is DispatchSlot) ||
    state.progress.entry is Some(_) ||
    state.progress.settlement is Some(_) ||
    state.physical_observer is Some(_) {
    return false
  }
  state.physical_observer = Some(observe)
  true
}

///|
fn observe_model_physical(
  state : ModelState,
  event : ModelPhysicalEvent,
) -> Unit {
  if state.physical_observer is Some(observe) &&
    state.attempts.get(state.progress.slot) is Some(trace) {
    observe({
      slot: state.progress.slot,
      attempt_cid: @publication.run_evidence_value_identity(trace.attempt),
      event,
    })
  }
}

///|
pub fn model_physical_observation_facts(
  value : ModelPhysicalObservation,
) -> (Int, String, String, String) {
  (
    value.slot,
    value.attempt_cid,
    match value.event {
      BeforeInvoke => "before_invoke"
      InvokeStarted => "started"
      InvokeReturned => "returned"
      InvokeFailed => "failed"
      InvokeCancelled => "cancelled"
    },
    match value.event {
      BeforeInvoke => "not_started"
      InvokeStarted => "running"
      InvokeReturned => "confirmed"
      InvokeFailed => "failed"
      InvokeCancelled => "cancelled"
    },
  )
}
