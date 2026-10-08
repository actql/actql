///|
pub enum ModelPhysicalEvent {
  InvokeStarted
  InvokeReturned
  InvokeFailed
  InvokeCancelled
}

///|
/// A diagnostic fact issued at actual invoke, not a dispatch permit, saved
/// response, usage receipt, or semantic completion. No payload is exposed.
pub struct ModelPhysicalObservation {
  slot : Int
  attempt_cid : String
  event : ModelPhysicalEvent
}

///|
/// Bind the installed Host's metadata-only observer to this exact live owner.
/// Delivery is outside the execution boundary; this hook only copies facts
/// and samples the physical clock. It cannot replace admission or enter_call.
pub fn bind_prepared_model_observation(
  value : ModelPreparedCallSet,
  observe : (ModelPhysicalObservation) -> Unit,
) -> Bool {
  let state = value.owner.state
  if !prepared_model_current(value) ||
    !(state.phase is DispatchSlot) ||
    state.entering is Some(_) ||
    state.settlement_pending is Some(_) ||
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
    state.attempts.get(state.next_slot) is Some(trace) {
    observe({
      slot: state.next_slot,
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
      InvokeStarted => "started"
      InvokeReturned => "returned"
      InvokeFailed => "failed"
      InvokeCancelled => "cancelled"
    },
    match value.event {
      InvokeStarted => "running"
      InvokeReturned => "confirmed"
      InvokeFailed => "failed"
      InvokeCancelled => "cancelled"
    },
  )
}
