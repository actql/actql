///|
// Same Model/Entry/attempt duty under Resource's original shared admission.
// All seven fields, the Slot reference and constructor overlap need original
// managed coverage. This private record is not a numerical profile or ACK.
priv struct ModelSlotIoDuty {
  access : @resources.ModelIoAccess
  lease : @resources.ModelIoLease
  reservation : @resources.Reservation
  slot : Int
  attempt : Int
  mut entry : ModelCallEntry?
  mut io_retired : Bool
}

///|
// Installation-only connection of the SAME opaque admission. Do not export a
// Node DATA/CID/Bool factory. Original startup/currentness and every admitted
// async physical Plan remain required; sync/generic do not gain IO support.
pub fn bind_prepared_model_io_access(
  prepared : ModelPreparedCallSet,
  access : @resources.ModelIoAccess,
) -> Result[Unit, ModelExecutionIssue] {
  let state = prepared.owner.state
  match check_model_original_resources_mutable(state) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard prepared_model_current(prepared) &&
    state.original_startup is Some(startup) && startup.used &&
    physical_equal(startup.ledger, state.ledger) &&
    physical_equal(startup.rows, state.rows) &&
    @resources.capacity_reservation_open(startup.capacity) &&
    state.progress.phase is DispatchSlot &&
    state.progress.entry is None && state.progress.call is None &&
    state.progress.settlement is None && state.progress.io_duty is None &&
    state.attempt_slots.is_empty() && prepared.io_access is None else {
    return Err(RequestIdentity)
  }
  for prepared_request in state.requests {
    guard state.physical_plans.get(prepared_request.request.slot) is Some(plan) &&
      physical_equal(plan.request, prepared_request.request) &&
      plan.invocation is Asynchronous(_) &&
      plan.response_profile is Some(profile) else {
      return Err(InvalidProvider)
    }
    let limits = @environment.model_response_profile_limits(profile)
    if !@resources.model_io_access_within_limits(
      access, limits.active_slots, limits.unsettled_slots,
    ) {
      return Err(IoAdmission(@resources.InvalidLimits))
    }
  }
  prepared.io_access = Some(access)
  Ok(())
}

///|
// Read-only availability is not a grant. Real claim is performed again by the
// bounded kernel before Entry/uncertain marking, preserving same work domain.
fn model_slot_io_available(state : ModelState) -> Result[Bool, ModelExecutionIssue] {
  guard state.prepared_call_set is Some(prepared) &&
    prepared.io_access is Some(access) &&
    state.progress.io_duty is None &&
    state.progress.phase is DispatchSlot &&
    state.progress.slot < state.requests.length() &&
    model_slot_send_eligible(state, state.progress.slot) else { return Ok(true) }
  guard state.reservations.get(state.progress.slot) is Some(reservation) else {
    return Err(RequestIdentity)
  }
  @resources.can_claim_model_io_access(
    access, state.ledger, reservation, state.progress.slot, 1,
  ).map_err(issue => IoAdmission(issue))
}

///|
fn claim_model_slot_io(state : ModelState) -> Result[Unit, ModelExecutionIssue] {
  guard state.prepared_call_set is Some(prepared) &&
    prepared.io_access is Some(access) else { return Ok(()) }
  if state.progress.io_duty is Some(duty) {
    guard duty.slot == state.progress.slot && duty.attempt == 1 &&
      physical_equal(duty.access, access) &&
      state.reservations.get(duty.slot) is Some(reservation) &&
      physical_equal(reservation, duty.reservation) else {
      return Err(RequestIdentity)
    }
    return Ok(())
  }
  guard state.reservations.get(state.progress.slot) is Some(reservation) else {
    return Err(RequestIdentity)
  }
  let lease = match @resources.claim_model_io_access(
    access, state.ledger, reservation, state.progress.slot, 1,
  ) {
    Err(issue) => return Err(IoAdmission(issue))
    Ok(lease) => lease
  }
  state.progress.io_duty = Some({
    access, lease, reservation, slot: state.progress.slot, attempt: 1,
    entry: None, io_retired: false,
  })
  Ok(())
}

///|
// Only the existing Common poll's SAME Call/Entry/Plan/reservation observation
// retires active IO. Neither response delivery nor SDK cleanup Bool issues it.
fn retire_model_slot_io_after_call_observation(
  state : ModelState,
  call : ModelPhysicalCall,
) -> Result[Unit, ModelExecutionIssue] {
  guard call.entry is Some(entry) && entry.progress.io_duty is Some(duty) else {
    return Ok(())
  }
  guard call.io_observation is Some(binding) &&
    physical_equal(binding.entry, entry) &&
    physical_equal(binding.reservation, duty.reservation) &&
    duty.entry is Some(original) && physical_equal(original, entry) &&
    duty.slot == entry.slot && duty.attempt == 1 else {
    return Err(RequestIdentity)
  }
  if duty.io_retired { return Ok(()) }
  match @resources.settle_model_io_lease_after_owner_ack(
    duty.access, duty.lease, state.ledger, duty.reservation, duty.slot, duty.attempt,
  ) {
    Err(issue) => return Err(IoAdmission(issue))
    Ok(_) => ()
  }
  duty.io_retired = true
  Ok(())
}

///|
// Only no Entry ever issued AND all original preflight children retired can
// establish this local never-started fact. A missing physical Call after an
// entered callback, cancellation or Unknown is deliberately NOT sufficient.
fn retire_model_slot_io_never_entered(state : ModelState) -> Bool {
  guard state.progress.io_duty is Some(duty) else { return true }
  if duty.entry is Some(_) || state.progress.call is Some(_) ||
    state.physical_cleanup_index != state.physical_cursors.length() {
    return false
  }
  if !duty.io_retired {
    match @resources.settle_model_io_lease_after_owner_ack(
      duty.access, duty.lease, state.ledger, duty.reservation, duty.slot, duty.attempt,
    ) {
      Err(_) => return false
      Ok(_) => duty.io_retired = true
    }
  }
  match @resources.settle_model_io_lease_holding_after_owner_ack(
    duty.access, duty.lease, state.ledger, duty.reservation, duty.slot, duty.attempt,
  ) {
    Err(_) => false
    Ok(_) => {
      state.progress.io_duty = None
      true
    }
  }
}

///|
// This follows the same Store/Journal settlement ACK AND actual physical/SDK
// cleanup. A failed Resource retirement keeps the original call/duty; physical
// cleanup must not run a second time simply because the final release failed.
fn retire_model_slot_io_holding(
  state : ModelState,
  call : ModelPhysicalCall,
) -> Bool {
  guard call.entry is Some(entry) && entry.progress.io_duty is Some(duty) else {
    return true
  }
  if !call.retired || !call.settlement_acknowledged || !duty.io_retired ||
    duty.entry is None || !physical_equal(duty.entry.unwrap(), entry) {
    return false
  }
  match @resources.settle_model_io_lease_holding_after_owner_ack(
    duty.access, duty.lease, state.ledger, duty.reservation, duty.slot, duty.attempt,
  ) {
    Err(_) => false
    Ok(_) => {
      duty.entry = None
      entry.progress.io_duty = None
      true
    }
  }
}
