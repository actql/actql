///|
/// An additional byte-only borrow of the existing original Model owner. This
/// is not another Ledger, a send reservation, a physical cleanup ACK or a
/// normal installed profile. Its original references, two byte amounts and representation
/// must be included in the supplier's simultaneous envelope before issuance.
struct OriginalModelPublicationCapacity {
  mut owner : ModelExecution?
  mut capacity : @resources.CapacityReservation?
  retained_bytes : Int64
  execution_bytes : Int64
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
  match
    check_original_mock_capacity(
      execution.state,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let shared = execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(_)
  if shared {
    execution.advancing = true
  }
  let capacity = match
    @resources.reserve_capacity(
      execution.state.ledger,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => {
      if shared {
        execution.advancing = false
      }
      return Err(Ledger(issue))
    }
    Ok(value) => value
  }
  // No callback/await separates the reservation from this original borrow.
  // Refusal above changes neither the use count nor the capacity serial.
  execution.state.output_uses += 1
  if execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) {
    purpose.publication_retained += retained_bytes
    purpose.publication_execution += execution_bytes
  }
  if shared {
    execution.advancing = false
  }
  Ok({
    owner: Some(execution),
    capacity: Some(capacity),
    retained_bytes,
    execution_bytes,
  })
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
  value.capacity is Some(capacity) &&
  physical_equal(original, execution) &&
  original_model_publication_owner_current(execution, scope) &&
  check_model_original_resources_mutable(execution.state) is Ok(_) &&
  @resources.capacity_reservation_covers(
    execution.state.ledger,
    capacity,
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
    return if value.capacity is None { Ok(true) } else { Err(OutputIdentity) }
  }
  guard value.capacity is Some(capacity) &&
    execution.state.call_scope is Some(scope) &&
    original_model_publication_owner_current(execution, scope) &&
    execution.state.output_uses > 0 &&
    @resources.capacity_reservation_covers(
      execution.state.ledger,
      capacity,
      0L,
      0L,
    ) else {
    return Err(OutputIdentity)
  }
  match check_model_original_resources_mutable(execution.state) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) &&
    (
      purpose.publication_retained < value.retained_bytes ||
      purpose.publication_execution < value.execution_bytes
    ) {
    return Err(OutputIdentity)
  }
  let shared = execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(_)
  if shared {
    execution.advancing = true
  }
  match @resources.settle_capacity(execution.state.ledger, capacity) {
    Err(issue) => {
      if shared {
        execution.advancing = false
      }
      return Err(Ledger(issue))
    }
    Ok(_) => ()
  }
  execution.state.output_uses -= 1
  if execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) {
    purpose.publication_retained -= value.retained_bytes
    purpose.publication_execution -= value.execution_bytes
  }
  // Retired handles cannot keep the original Model graph alive without funds.
  value.owner = None
  // The closed Resource token also points back to its Ledger/inventory. Do not
  // leave that back-reference in an escaped retired publication handle.
  value.capacity = None
  if shared {
    execution.advancing = false
  }
  Ok(true)
}

///|
/// A sibling original Model may share this publication funding only on the
/// SAME physical parent Ledger. This observes existing original Scope/current
/// and reservation identity; it exports no Ledger, grant or cleanup proof.
pub fn original_model_publication_capacity_matches_parent(
  value : OriginalModelPublicationCapacity,
  execution : ModelExecution,
  scope : @publication_host.ClientInferCallScope,
) -> Bool {
  guard value.owner is Some(original) && value.capacity is Some(_) else {
    return false
  }
  // The enclosing aggregate checks this borrow's mutable/current fence once.
  // All siblings then match that SAME Ledger with pure original identities;
  // no extra owner callback is needed at the same synchronous boundary.
  original_model_publication_owner_current(execution, scope) &&
  physical_equal(original.state.ledger, execution.state.ledger)
}
