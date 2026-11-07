///|
/// Parent-local live accounting access, not a serializable child pointer.
/// R is the trusted physical Owner's original channel/VM/FD/domain carrier.
/// All records, resident flags and reference overlap need original funding.
pub struct BackedExecutionLiveAccess[P, C, R] {
  priv mut original : BackedExecutionLiveAccess[P, C, R]?
  priv mut region : BackedExecutionRegion[P, C]?
  priv mut provider : P?
  priv mut child : C?
  priv mut ticket : BackedExecutionDelegation[P, C]?
  priv mut read_use : BackedExecutionReadUse[P, C]?
  priv mut runtime : R?
  priv mut projection : BackedExecutionLiveProjection[P, C, R]?
  // Direct original child accounting only. The physical Owner's final ACK
  // clears its captured callbacks; this is not another cleanup Owner.
  priv mut child_origin : ImportedChildLedgerOrigin?
  priv mut closing : Bool
}

///|
/// A single admitted view of the existing delegated allowance. No fresh
/// Ledger, reservation or quota is created. Physical transport/adoption into
/// a different runtime remains the trusted installed Owner's responsibility.
pub struct BackedExecutionLiveProjection[P, C, R] {
  priv mut access : BackedExecutionLiveAccess[P, C, R]?
  priv mut child_ledger_issued : Bool
  priv mut retired_after_owner_ack : Bool
}

///|
/// Original lifetime observation, not allocation/send/stop permission.
pub(all) enum BackedExecutionLiveState {
  LiveOpen
  LiveClosing
} derive(Eq, Debug)

///|
/// Call before the same physical bootstrap. Equal DATA, IDs and wire cannot
/// supply runtime identity. A lost reply keeps this same one-shot access.
pub fn[P, C, R] issue_backed_execution_live_access(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  read_use : BackedExecutionReadUse[P, C],
  runtime : R,
) -> Result[BackedExecutionLiveAccess[P, C, R], BackedExecutionIssue] {
  match
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if read_use.live_access_issued {
    return Err(LiveAccessAlreadyIssued)
  }
  let access : BackedExecutionLiveAccess[P, C, R] = {
    original: None,
    region: Some(region),
    provider: Some(provider),
    child: Some(child),
    ticket: Some(ticket),
    read_use: Some(read_use),
    runtime: Some(runtime),
    projection: None,
    child_origin: None,
    closing: false,
  }
  access.original = Some(access)
  read_use.live_access_issued = true
  read_use.live_access_pending = true
  Ok(access)
}

///|
fn[P, C, R] backed_live_original(
  access : BackedExecutionLiveAccess[P, C, R],
  runtime : R,
) -> Result[
  (
    BackedExecutionRegion[P, C],
    P,
    C,
    BackedExecutionDelegation[P, C],
    BackedExecutionReadUse[P, C],
  ),
  BackedExecutionIssue,
] {
  guard access.original is Some(original) else { return Err(Retired) }
  if !physical_equal(original, access) {
    return Err(ForeignOriginal)
  }
  guard access.runtime is Some(selected) && physical_equal(selected, runtime) else {
    return Err(ForeignOriginal)
  }
  guard access.region is Some(region) &&
    access.provider is Some(provider) &&
    access.child is Some(child) &&
    access.ticket is Some(ticket) &&
    access.read_use is Some(read_use) else {
    return Err(Retired)
  }
  match backed_read_use_current(region, provider, child, ticket, read_use) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !read_use.live_access_pending || !ticket.logical.unwrap().reservation.open {
    return Err(Retired)
  }
  Ok((region, provider, child, ticket, read_use))
}

///|
/// One original admission even if its reply is lost. This does not return a
/// bare Ledger or grant Source, Model, launch, restore or settlement authority.
pub fn[P, C, R] admit_backed_execution_live_child(
  access : BackedExecutionLiveAccess[P, C, R],
  runtime : R,
) -> Result[BackedExecutionLiveProjection[P, C, R], BackedExecutionIssue] {
  let (region, provider, child, ticket, read_use) = match
    backed_live_original(access, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if access.closing {
    return Err(RegionClosing)
  }
  match
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if access.projection is Some(_) {
    return Err(LiveChildAlreadyAdmitted)
  }
  // First bootstrap only. Do not manufacture a new zero-based child view
  // after any usage/peak was already reported through this original ticket.
  if !backed_child_usage_unreported(ticket) {
    return Err(Resource(InvalidCharge))
  }
  let projection : BackedExecutionLiveProjection[P, C, R] = {
    access: Some(access),
    child_ledger_issued: false,
    retired_after_owner_ack: false,
  }
  access.projection = Some(projection)
  Ok(projection)
}

///|
fn[P, C, R] backed_live_projection_original(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
) -> Result[BackedExecutionLiveAccess[P, C, R], BackedExecutionIssue] {
  guard projection.access is Some(access) else { return Err(Retired) }
  match backed_live_original(access, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard access.projection is Some(original) &&
    physical_equal(original, projection) else {
    return Err(ForeignOriginal)
  }
  Ok(access)
}

///|
/// Observe the same original without charging a report or substituting a
/// failed limits read for currentness. Closing retains entered cleanup duty.
pub fn[P, C, R] backed_execution_live_state(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
) -> Result[BackedExecutionLiveState, BackedExecutionIssue] {
  let access = match backed_live_projection_original(projection, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (region, _, _, _, read_use) = match
    backed_live_original(access, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if access.closing ||
    region.closing ||
    (region.working is Some((working, _, _)) && working.closing) ||
    read_use.closing ||
    region.capacity.unwrap().closing {
    Ok(LiveClosing)
  } else {
    Ok(LiveOpen)
  }
}

///|
/// Read-only limits from the same live parent. A copy is DATA, not admission.
/// Closing forbids new child work but does not cancel entered cleanup/report.
pub fn[P, C, R] backed_execution_live_limits(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
) -> Result[LedgerLimits, BackedExecutionIssue] {
  let access = match backed_live_projection_original(projection, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (region, provider, child, ticket, read_use) = match
    backed_live_original(access, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if access.closing {
    return Err(RegionClosing)
  }
  match
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(ticket.limits)
  }
}

///|
/// Cumulative bounded DATA is applied only to this original parent ticket.
/// Closing still permits original cleanup accounting. No callback/retry/ACK
/// is created, and failed reports do not reset usage or replace the access.
pub fn[P, C, R] report_backed_execution_live_child(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
  usage : LedgerUsage,
) -> Result[Unit, BackedExecutionIssue] {
  let access = match backed_live_projection_original(projection, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (region, provider, child, ticket, _) = match
    backed_live_original(access, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  report_backed_execution_delegation(region, provider, child, ticket, usage)
}

///|
/// Logical stop only. Keep the original access, report and physical custody.
pub fn[P, C, R] stop_backed_execution_live_child(
  access : BackedExecutionLiveAccess[P, C, R],
  runtime : R,
) -> Result[Unit, BackedExecutionIssue] {
  match backed_live_original(access, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The same original child already exists inside this synchronous stop.
  // Publish its restriction before a consuming callback can return; the
  // imported post-current fence must not wait for another external callback.
  if access.child_origin is Some(origin) {
    origin.stopping = true
  }
  if access.ticket is Some(ticket) && ticket.current_window is Some(_) &&
    access.read_use is Some(read_use) {
    read_use.closing = true
  }
  access.closing = true
  Ok(())
}

///|
/// Trusted physical Owner only, AFTER this same runtime/channel/reader and
/// escaped projection aliases actually retire. Unknown or cancellation is
/// not this observation. Break both reference cycles but return no borrow,
/// quota, capacity or Store custody; their separate ACK APIs remain required.
pub fn[P, C, R] retire_backed_execution_live_child_after_owner_ack(
  access : BackedExecutionLiveAccess[P, C, R],
  runtime : R,
) -> Result[Unit, BackedExecutionIssue] {
  let (_, _, _, _, read_use) = match backed_live_original(access, runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if access.projection is Some(projection) {
    projection.retired_after_owner_ack = true
    projection.access = None
  }
  if access.child_origin is Some(origin) {
    retire_backed_original_child_origin(origin)
    access.child_origin = None
  }
  read_use.live_access_pending = false
  access.closing = true
  access.original = None
  access.region = None
  access.provider = None
  access.child = None
  access.ticket = None
  access.read_use = None
  access.runtime = None
  access.projection = None
  Ok(())
}
