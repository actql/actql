///|
/// Nominal acknowledgement of the original installed journal operation.
/// The trusted persistence adapter issues this only after saving the exact
/// entry originals; equal strings or a historical attempt cannot recreate it.
/// This handle is not a new journal, authority or proof of physical send.
pub struct ModelCallEntryAcknowledgement {
  entry : ModelCallEntry
}

///|
/// One final synchronous start permission for an original entry. No awaiting,
/// request reconstruction or arbitrary callback belongs between consumption
/// and the fixed transport start. It cannot be serialized or reused.
priv struct ModelCallSendGate {
  entry : ModelCallEntry
}

///|
pub fn acknowledge_model_call_entry(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
) -> ModelCallEntryAcknowledgement? {
  if !model_call_entry_current(entry, prepared) || entry.send_started {
    return None
  }
  if entry.acknowledgement is Some(original) {
    return Some(original)
  }
  let acknowledgement : ModelCallEntryAcknowledgement = { entry, }
  entry.acknowledgement = Some(acknowledgement)
  Some(acknowledgement)
}

///|
pub fn model_call_entry_acknowledgement_current(
  value : ModelCallEntryAcknowledgement,
  prepared : ModelPreparedCallSet,
) -> Bool {
  value.entry.acknowledgement is Some(original) &&
  physical_equal(original, value) &&
  !value.entry.send_started &&
  model_call_entry_current(value.entry, prepared)
}

///|
fn model_call_start_current(
  entry : ModelCallEntry,
  reader : @bounded.Reader,
) -> Result[Unit, ModelExecutionIssue] {
  let state = entry.prepared.owner.state
  if @bounded.stop_requested(reader) is Some(reason) {
    return Err(
      match reason {
        @bounded.Cancelled => Cancelled
        @bounded.Deadline => Deadline
      },
    )
  }
  if state.stop_requested {
    return Err(Cancelled)
  }
  // Observe the original current authorities again after entry persistence,
  // including immediate acknowledgements. Do not reuse its pre-await result.
  match @publication_host.check_client_infer_dispatch_current(entry.admission) {
    Err(issue) => return Err(Authorization(issue))
    Ok(_) => ()
  }
  if state.egress_admission is Some(admission) {
    match @publication_host.check_client_infer_egress_current(admission) {
      Err(issue) => return Err(Egress(issue))
      Ok(_) => ()
    }
  }
  guard model_call_entry_current(entry, entry.prepared) &&
    !entry.send_started &&
    model_slot_send_eligible(state, entry.slot) &&
    state.requests.get(entry.slot) is Some(prepared) &&
    prepared.call is Some(call) &&
    physical_equal(call, entry.trace.call) &&
    state.reservations.get(entry.slot) is Some(reservation) &&
    @resources.reservation_open(reservation) else {
    return Err(CallEntryRefused)
  }
  if state.physical_preflight is Some(_) {
    guard state.physical_plans.get(entry.slot) is Some(plan) &&
      physical_equal(plan.request, prepared.request) else {
      return Err(RequestIdentity)
    }
  }
  Ok(())
}

///|
fn issue_model_call_send_gate(
  acknowledgement : ModelCallEntryAcknowledgement,
  reader : @bounded.Reader,
) -> Result[ModelCallSendGate, ModelExecutionIssue] {
  let entry = acknowledgement.entry
  if !model_call_entry_acknowledgement_current(acknowledgement, entry.prepared) ||
    entry.gate_issued {
    return Err(CallEntryRefused)
  }
  match model_call_start_current(entry, reader) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  entry.gate_issued = true
  Ok({ entry, })
}

///|
fn consume_model_call_send_gate(
  gate : ModelCallSendGate,
  reader : @bounded.Reader,
) -> Result[Unit, ModelExecutionIssue] {
  let entry = gate.entry
  if entry.acknowledgement is None || !entry.gate_issued || entry.send_started {
    return Err(CallEntryRefused)
  }
  match model_call_start_current(entry, reader) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  entry.send_started = true
  Ok(())
}

///|
// Legacy non-durable callers still use their existing current authorities.
// A diagnostic callback cannot turn its earlier checks into send permission.
fn check_model_physical_start_current(
  state : ModelState,
  reader : @bounded.Reader,
) -> Result[Unit, ModelExecutionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return Err(
      match reason {
        @bounded.Cancelled => Cancelled
        @bounded.Deadline => Deadline
      },
    )
  }
  if state.stop_requested {
    return Err(Cancelled)
  }
  if state.dispatch_admission is Some(admission) {
    match @publication_host.check_client_infer_dispatch_current(admission) {
      Err(issue) => return Err(Authorization(issue))
      Ok(_) => ()
    }
  }
  if state.egress_admission is Some(admission) {
    match @publication_host.check_client_infer_egress_current(admission) {
      Err(issue) => return Err(Egress(issue))
      Ok(_) => ()
    }
  }
  guard model_slot_send_eligible(state, state.next_slot) &&
    state.reservations.get(state.next_slot) is Some(reservation) &&
    @resources.reservation_open(reservation) else {
    return Err(CallEntryRefused)
  }
  Ok(())
}
