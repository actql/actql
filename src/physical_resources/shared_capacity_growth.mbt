///|
/// One pending physical addition to the SAME reservation and control claim.
/// This is not another allocator, reservation, borrower or attempt. Its original
/// supplier funds this small carrier before beginning the acquisition.
struct SharedCapacityGrowth {
  owner : SharedCapacity
  control : SharedAllocation
  before : Int64
  after : Int64
  control_before : Int64
  control_additional : Int64
}

///|
/// Reserve complete new mapping and its actual control prefix before acquisition.
/// Existing borrowers keep their exact tokens and the old payload never moves.
/// While pending, no allocation or new borrower may consume the proposed suffix.
pub fn begin_shared_capacity_growth(
  owner : SharedCapacity,
  control : SharedAllocation,
  bytes : Int64,
  control_additional : Int64,
) -> Result[SharedCapacityGrowth, LedgerIssue] {
  match reservation_check(owner.ledger, owner.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.ledger.imported_child is Some(_) {
    return Err(ChildFundingUnavailable)
  }
  if !physical_equal(control.owner, owner) {
    return Err(ForeignOwner)
  }
  if owner.closing ||
    owner.growth is Some(_) ||
    control.retiring ||
    control.released {
    return Err(ClosedHolding)
  }
  if bytes <= owner.capacity ||
    control_additional <= 0L ||
    control_additional >= bytes - owner.capacity ||
    owner.reservation.execution != owner.capacity {
    return Err(InvalidCharge)
  }
  match
    grow_execution_reservation_capacity_current(
      owner.ledger,
      owner.reservation,
      owner.reservation.retention,
      bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let growth = {
    owner,
    control,
    before: owner.capacity,
    after: bytes,
    control_before: control.bytes,
    control_additional,
  }
  owner.capacity = bytes
  owner.allocated += control_additional
  control.bytes += control_additional
  owner.growth = Some(growth)
  Ok(growth)
}

///|
fn check_shared_capacity_growth_current(
  growth : SharedCapacityGrowth,
) -> Result[Unit, LedgerIssue] {
  let owner = growth.owner
  match reservation_check_current(owner.ledger, owner.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.growth is Some(original) && physical_equal(original, growth) else {
    return Err(ForeignOwner)
  }
  if owner.capacity != growth.after ||
    owner.reservation.execution != growth.after ||
    growth.control.released ||
    growth.control.bytes != growth.control_before + growth.control_additional ||
    owner.allocated < growth.control_additional ||
    owner.allocated - growth.control_additional > growth.before {
    return Err(InvalidCharge)
  }
  Ok(())
}

///|
/// The original trusted supplier calls this only after actual acquisition.
/// Unknown/lost outcome stays pending and charged; it is never treated as zero.
pub fn complete_shared_capacity_growth_after_acquisition(
  growth : SharedCapacityGrowth,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(growth.owner.ledger, growth.owner.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_shared_capacity_growth_current(growth) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  growth.owner.growth = None
  Ok(())
}

///|
/// Only after an atomic failed acquisition or confirmed physical cleanup of
/// this exact addition. It can return only the recorded, unconstructed suffix;
/// no old borrower bytes, attempt, transfer, quantity or serial are restored.
pub fn abort_shared_capacity_growth_after_cleanup(
  growth : SharedCapacityGrowth,
) -> Result[Unit, LedgerIssue] {
  let owner = growth.owner
  match reservation_check(owner.ledger, owner.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_shared_capacity_growth_current(growth) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Same closed current cut as canonical resize. No callback can intervene
  // between suffix validation, reservation return and original amount update.
  match
    resize_reservation_bytes_current(
      owner.ledger,
      owner.reservation,
      owner.reservation.retention,
      growth.before,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.capacity = growth.before
  owner.allocated -= growth.control_additional
  growth.control.bytes = growth.control_before
  owner.growth = None
  Ok(())
}
