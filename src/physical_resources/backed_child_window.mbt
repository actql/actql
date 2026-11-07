///|
/// Check declared policy for the SAME child before its physical owner reserves
/// and acquires an addition. This observes currentness but grants no bytes,
/// resizes no Read and cannot be retained as a reusable admission proof.
pub fn[P, C, R] check_backed_original_child_window_demand(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, BackedExecutionIssue] {
  let ticket = match backed_original_child_window_current(projection, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if retained < 0L ||
    execution < 0L ||
    retained > ticket.limits.retained_bytes ||
    execution > ticket.limits.execution_bytes {
    return Err(Resource(InvalidLimits))
  }
  Ok(())
}

///|
/// Observe the SAME child's acquired usable pool, not its declared limits or
/// contiguous allocation geometry. No bytes are granted or Read resized; a
/// later reservation still checks its actual simultaneous demand/currentness.
pub fn[P, C, R] read_backed_original_child_window_bytes(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
) -> Result[Int64, BackedExecutionIssue] {
  match backed_original_child_window_current(projection, runtime) {
    Ok(ticket) => Ok(ticket.current_window.unwrap().val)
    Err(issue) => Err(issue)
  }
}

///|
// Shared original-current fence for policy and acquired-pool observations.
// This returns no reusable current proof outside this Resource owner.
fn[P, C, R] backed_original_child_window_current(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
) -> Result[BackedExecutionDelegation[P, C], BackedExecutionIssue] {
  let access = match backed_live_projection_original(projection, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard access.ticket is Some(ticket) && ticket.current_window is Some(_) else {
    return Err(InvalidExtent)
  }
  guard access.region is Some(region) &&
    region.capacity is Some(capacity) &&
    access.read_use is Some(read_use) else {
    return Err(Retired)
  }
  if access.closing ||
    region.closing ||
    capacity.closing ||
    read_use.closing ||
    (access.child_origin is Some(origin) && origin.stopping) {
    return Err(RegionClosing)
  }
  Ok(ticket)
}

///|
/// The existing trusted physical owner calls ONLY after actual acquisition of
/// this pending parent growth. Its receipt supplies usable bytes, excluding
/// control/receipt overhead. Discontiguous Native suffixes remain charged in
/// the original control allocation: the mapped extent/address never expands.
///
/// Complete that SAME growth and publish the SAME child's backed window in
/// one closed current cut. Only a later canonical Read resize can grant use.
/// Failure/Unknown retains the pending growth, old window and physical duties.
pub fn[P, C, R] complete_backed_original_child_window_after_acquisition(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
  growth : SharedCapacityGrowth,
  acquired_payload_bytes : Int64,
) -> Result[Unit, BackedExecutionIssue] {
  let access = match backed_live_projection_original(projection, runtime) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if access.closing || (access.child_origin is Some(origin) && origin.stopping) {
    return Err(RegionClosing)
  }
  guard access.region is Some(region) && access.ticket is Some(ticket) else {
    return Err(Retired)
  }
  complete_backed_execution_window_current(
    region, ticket, growth, acquired_payload_bytes,
  )
}

///|
/// The same physical-owner operation before a live projection/child Ledger
/// exists. No synthetic runtime, projection, Ledger or Root is manufactured.
/// Receipt and cleanup obligations are identical to the wrapper above.
pub fn[P, C] complete_backed_execution_window_after_acquisition(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  growth : SharedCapacityGrowth,
  acquired_payload_bytes : Int64,
) -> Result[Unit, BackedExecutionIssue] {
  match
    check_backed_execution_delegation_current(region, provider, child, ticket) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  complete_backed_execution_window_current(
    region, ticket, growth, acquired_payload_bytes,
  )
}

///|
// Same owner after its original-current fence. No callback or reusable current
// proof escapes between this validation and pending-growth/window publication.
fn[P, C] complete_backed_execution_window_current(
  region : BackedExecutionRegion[P, C],
  ticket : BackedExecutionDelegation[P, C],
  growth : SharedCapacityGrowth,
  acquired_payload_bytes : Int64,
) -> Result[Unit, BackedExecutionIssue] {
  // No callback follows this original-current check before publication.
  guard region.capacity is Some(capacity) &&
    ticket.current_window is Some(window) &&
    region.working is None &&
    ticket.access == ExclusiveWrite &&
    region.children.length() == 1 &&
    physical_equal(growth.owner, capacity) else {
    return Err(ForeignOriginal)
  }
  if region.closing ||
    capacity.closing ||
    (ticket.read_use is Some(read_use) && read_use.closing) {
    return Err(RegionClosing)
  }
  let before = window.val
  if acquired_payload_bytes <= 0L ||
    acquired_payload_bytes > growth.control_additional ||
    acquired_payload_bytes > 9223372036854775807L - before {
    return Err(InvalidExtent)
  }
  match check_shared_capacity_growth_current(growth) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  // Existing completion state, not another receipt/ACK or resource issuer.
  // The new physical pool carries no arbitrary retained/execution partition.
  growth.owner.growth = None
  window.val = before + acquired_payload_bytes
  Ok(())
}
