///|
/// A read/workspace borrow of the original backed child, within this Resource
/// Owner. It neither authenticates a restored census nor grants read authority.
/// Its control and callback/physical overhead require separate real funding.
pub struct BackedExecutionReadUse[P, C] {
  mut ticket : BackedExecutionDelegation[P, C]?
  mut borrow : SharedBorrow?
  mut closing : Bool
  // Resident flags and any live access/projection controls require the same
  // original envelope. They are not another byte reservation or ACK.
  priv mut live_access_issued : Bool
  priv mut live_access_pending : Bool
}

///|
/// Claim before constructing the physical read context or opening a Root/FD.
/// Managed read results write the selected payload, so ReadOnly is inadequate.
/// Bytes are already reserved by this same region; no second reserve or new
/// logical quota is issued. Ordinary borrowing remains retired by its Owner.
pub fn[P, C] borrow_backed_execution_read_use(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
) -> Result[BackedExecutionReadUse[P, C], BackedExecutionIssue] {
  let (capacity, _, logical) = match
    backed_child_current(region, provider, child, ticket) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if region.closing || capacity.closing {
    return Err(RegionClosing)
  }
  if !logical.reservation.open {
    return Err(Retired)
  }
  if ticket.read_use_issued {
    return Err(ReadUseAlreadyIssued)
  }
  if ticket.access != ExclusiveWrite {
    return Err(InvalidExtent)
  }
  let allocation = ticket.borrow.unwrap().allocation
  if allocation.readers == 2147483647 {
    return Err(Resource(InvalidCharge))
  }
  allocation.readers += 1
  let borrow : SharedBorrow = { allocation, returned: false, }
  let read_use : BackedExecutionReadUse[P, C] = {
    ticket: Some(ticket),
    borrow: Some(borrow),
    closing: false,
    live_access_issued: false,
    live_access_pending: false,
  }
  ticket.read_use_issued = true
  ticket.read_use = Some(read_use)
  Ok(read_use)
}

///|
fn[P, C] backed_read_use_current(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  read_use : BackedExecutionReadUse[P, C],
) -> Result[Unit, BackedExecutionIssue] {
  // Current-only callers need no quota/extent projection or temporary tuple.
  // Reuse the same original child checks before inspecting this read borrow.
  match
    check_backed_execution_delegation_current(region, provider, child, ticket) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard ticket.borrow is Some(original_borrow) else {
    return Err(ForeignOriginal)
  }
  let allocation = original_borrow.allocation
  guard read_use.ticket is Some(original) &&
    physical_equal(original, ticket) &&
    ticket.read_use is Some(selected) &&
    physical_equal(selected, read_use) &&
    read_use.borrow is Some(borrow) else {
    return Err(ForeignOriginal)
  }
  if !physical_equal(borrow.allocation, allocation) ||
    borrow.returned ||
    allocation.readers < 3 {
    return Err(Retired)
  }
  Ok(())
}

///|
/// Keep the exact original ticket/extent/current check at foreign callers.
/// This is not a physical ACK, an installation proof or Source/read permission.
pub fn[P, C] require_backed_execution_read_use_current(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  read_use : BackedExecutionReadUse[P, C],
) -> Result[Unit, BackedExecutionIssue] {
  match backed_read_use_current(region, provider, child, ticket, read_use) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if region.closing ||
    read_use.closing ||
    region.capacity.unwrap().closing ||
    (region.working is Some((working, _, _)) && working.closing) {
    Err(RegionClosing)
  } else {
    Ok(())
  }
}

///|
/// Logical closing returns no capacity. The original physical Owner may still
/// finish same-context cleanup; cancellation/EOF/death is not its completion.
pub fn[P, C] stop_backed_execution_read_use(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  read_use : BackedExecutionReadUse[P, C],
) -> Result[Unit, BackedExecutionIssue] {
  match backed_read_use_current(region, provider, child, ticket, read_use) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  read_use.closing = true
  Ok(())
}

///|
/// Existing trusted physical Owner only, AFTER original Root/Reader ACK, last
/// aliases and the same physical context retirement. Failed/unknown cleanup
/// keeps this same use. This returns only its read borrow: parent delegation,
/// byte reservation, process stop and Store/Provider outcomes stay separate.
pub fn[P, C] return_backed_execution_read_use_after_owner_ack(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  read_use : BackedExecutionReadUse[P, C],
) -> Result[Unit, BackedExecutionIssue] {
  match backed_read_use_current(region, provider, child, ticket, read_use) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Only the actual return path needs this reference. No callback/await or
  // mutation separates it from the original identity/lifetime checks above.
  guard read_use.borrow is Some(borrow) else { return Err(ForeignOriginal) }
  if read_use.live_access_pending {
    return Err(CleanupPending)
  }
  read_use.closing = true
  match return_shared_capacity(borrow) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  ticket.read_use = None
  read_use.ticket = None
  read_use.borrow = None
  Ok(())
}
