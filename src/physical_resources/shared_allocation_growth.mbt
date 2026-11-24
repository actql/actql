///|
/// Extend the same unborrowed control claim inside already acquired capacity.
/// The physical owner separately proves its constructor geometry and actual
/// storage before entry. This never grows a retired delegated extent, creates
/// another reservation, or treats a policy ceiling as backing.
pub fn grow_unborrowed_shared_allocation(
  owner : SharedCapacity,
  allocation : SharedAllocation,
  expected_bytes : Int64,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  match check_imported_child_admission(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_original_resources_mutable(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(allocation.owner, owner) {
    return Err(ForeignOwner)
  }
  if owner.closing ||
    owner.growth is Some(_) ||
    !reservation_open(owner.reservation) ||
    allocation.retiring ||
    allocation.released ||
    allocation.readers != 0 {
    return Err(ClosedHolding)
  }
  if expected_bytes != allocation.bytes || bytes < expected_bytes {
    return Err(InvalidCharge)
  }
  let additional = bytes - expected_bytes
  if additional > owner.capacity - owner.allocated {
    return Err(RetentionLimit)
  }
  owner.allocated += additional
  allocation.bytes = bytes
  Ok(())
}

///|
/// Reconcile only acknowledged retired storage in the SAME unborrowed control
/// claim. The trusted physical owner must have completed its original cleanup
/// before supplying the remaining amount. Whole backing stays reserved; no
/// attempt, work, transfer or quantity is refunded or issued by this update.
pub fn reconcile_unborrowed_shared_allocation_after_cleanup(
  owner : SharedCapacity,
  allocation : SharedAllocation,
  expected_bytes : Int64,
  remaining_bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(allocation.owner, owner) {
    return Err(ForeignOwner)
  }
  match reservation_check(owner.ledger, owner.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Recheck these originals after the one current callback. A stale amount,
  // active borrower, pending growth or retirement cannot supply cleanup credit.
  if owner.closing ||
    owner.growth is Some(_) ||
    allocation.retiring ||
    allocation.released ||
    allocation.readers != 0 {
    return Err(ClosedHolding)
  }
  if expected_bytes != allocation.bytes ||
    remaining_bytes < 0L ||
    remaining_bytes > expected_bytes ||
    owner.allocated < expected_bytes {
    return Err(InvalidCharge)
  }
  owner.allocated -= expected_bytes - remaining_bytes
  allocation.bytes = remaining_bytes
  Ok(())
}

///|
/// Reconcile an idle same-original copy reservation after its owner has
/// retired bytes. The remaining positive capacity still backs its controls.
pub fn reconcile_idle_shared_capacity_after_cleanup(
  owner : SharedCapacity,
  expected_bytes : Int64,
  remaining_bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(owner.ledger, owner.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.closing || owner.growth is Some(_) || owner.allocated != 0L {
    return Err(ClosedHolding)
  }
  if owner.capacity != expected_bytes ||
    owner.reservation.execution != expected_bytes ||
    remaining_bytes <= 0L ||
    remaining_bytes < owner.reservation.retention ||
    remaining_bytes > expected_bytes {
    return Err(InvalidCharge)
  }
  reduce_execution_reservation_current(
    owner.ledger,
    owner.reservation,
    remaining_bytes,
  ).map(_ => owner.capacity = remaining_bytes)
}
