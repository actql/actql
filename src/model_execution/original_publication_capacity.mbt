///|
/// An additional byte-only borrow of the existing original Model owner. This
/// is not another Ledger, a send reservation, a physical cleanup ACK or a
/// normal installed profile. Its two fields and optional-owner representation
/// must be included in the supplier's simultaneous envelope before issuance.
struct OriginalModelPublicationCapacity {
  mut owner : ModelExecution?
  capacity : @resources.CapacityReservation
}

///|
fn original_model_publication_owner_current(
  execution : ModelExecution,
  scope : @publication_host.ClientInferCallScope,
) -> Bool {
  let state = execution.state
  !execution.advancing &&
  !state.reclaimed &&
  state.accepted &&
  state.call_scope is Some(current) &&
  physical_equal(current, scope) &&
  @publication_host.client_infer_call_scope_matches_rows(
    scope,
    state.rows,
    state.fixed_request_cid,
  ) &&
  state.original_startup is Some(startup) &&
  startup.used &&
  physical_equal(startup.rows, state.rows) &&
  physical_equal(startup.ledger, state.ledger) &&
  startup.scope is Some(original) &&
  physical_equal(original, scope) &&
  @resources.capacity_reservation_matches(
    state.ledger,
    startup.capacity,
    startup.retained_bytes,
    startup.execution_bytes,
  )
}

///|
/// Reserve a separately justified publication retention/workspace envelope on
/// the same original Ledger before allocating additional publication state.
/// No byte policy is supplied here. The installed caller still owes a complete
/// bound for its actual buffers, trees, callbacks and overlapping aliases.
pub fn reserve_original_model_publication_capacity(
  execution : ModelExecution,
  scope : @publication_host.ClientInferCallScope,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[OriginalModelPublicationCapacity, ModelExecutionIssue] {
  if retained_bytes <= 0L || execution_bytes < 0L {
    return Err(InvalidLimits)
  }
  if !original_model_publication_owner_current(execution, scope) ||
    execution.state.stop_requested ||
    execution.state.output_uses == 2147483647 {
    return Err(OutputIdentity)
  }
  match check_model_original_resources_mutable(execution.state) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let capacity = match
    @resources.reserve_capacity(
      execution.state.ledger,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => return Err(Ledger(issue))
    Ok(value) => value
  }
  // No callback/await separates the reservation from this original borrow.
  // Refusal above changes neither the use count nor the capacity serial.
  execution.state.output_uses += 1
  Ok({ owner: Some(execution), capacity, })
}

///|
/// Match this live borrow to its actual original receiver without projecting
/// its Ledger/token. Equal limits or equal Run CIDs cannot substitute for the
/// nominal Model/Scope. A retired or parked borrow is not available for use.
pub fn original_model_publication_capacity_current(
  value : OriginalModelPublicationCapacity,
  execution : ModelExecution,
  scope : @publication_host.ClientInferCallScope,
) -> Bool {
  value.owner is Some(original) &&
  physical_equal(original, execution) &&
  original_model_publication_owner_current(execution, scope) &&
  check_model_original_resources_mutable(execution.state) is Ok(_) &&
  @resources.capacity_reservation_covers(
    execution.state.ledger,
    value.capacity,
    0L,
    0L,
  )
}

///|
/// Invoke only after the existing publication/Store caller has retired its
/// actual physical and alias custody. This function proves token ownership,
/// not that external cleanup happened; cancellation, COMMIT or dropping a
/// String alone must not call it. Failed settlement keeps the exact borrow.
pub fn release_original_model_publication_capacity(
  value : OriginalModelPublicationCapacity,
) -> Result[Bool, ModelExecutionIssue] {
  guard value.owner is Some(execution) else {
    return Ok(!@resources.capacity_reservation_open(value.capacity))
  }
  guard execution.state.call_scope is Some(scope) &&
    original_model_publication_owner_current(execution, scope) &&
    execution.state.output_uses > 0 &&
    @resources.capacity_reservation_covers(
      execution.state.ledger,
      value.capacity,
      0L,
      0L,
    ) else {
    return Err(OutputIdentity)
  }
  match check_model_original_resources_mutable(execution.state) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.settle_capacity(execution.state.ledger, value.capacity) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  execution.state.output_uses -= 1
  // Retired handles cannot keep the original Model graph alive without funds.
  value.owner = None
  Ok(true)
}
