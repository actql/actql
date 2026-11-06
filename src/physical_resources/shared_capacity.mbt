///|
/// One owned execution-resource reservation. Retained copy allowances are
/// suballocations of this capacity, not additional Host retained allocations.
struct SharedCapacity {
  ledger : Ledger
  reservation : Reservation
  mut capacity : Int64
  mut allocated : Int64
  mut closing : Bool
  mut growth : SharedCapacityGrowth?
}

///|
struct SharedAllocation {
  owner : SharedCapacity
  mut bytes : Int64
  mut readers : Int
  mut retiring : Bool
  mut released : Bool
}

///|
pub fn reserve_shared_capacity(
  ledger : Ledger,
  bytes : Int64,
) -> Result[SharedCapacity, LedgerIssue] {
  if bytes <= 0L {
    return Err(InvalidCharge)
  }
  match reserve_attempt(ledger, 0L, 0L, bytes) {
    Err(issue) => Err(issue)
    Ok(reservation) =>
      Ok({
        ledger,
        reservation,
        capacity: bytes,
        allocated: 0L,
        closing: false,
        growth: None,
      })
  }
}

///|
/// Byte-only execution workspace on the same original Ledger. Unlike the
/// existing resident/send-attempt entry, this consumes no attempt, transfer
/// or quantity allowance. The original phase supplier must still select and
/// retain the complete envelope before allocation; free bytes or this token
/// alone establish neither phase assignment nor permission to read or send.
pub fn reserve_shared_workspace_capacity(
  ledger : Ledger,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[SharedCapacity, LedgerIssue] {
  if retained_bytes < 0L ||
    execution_bytes <= 0L ||
    execution_bytes < retained_bytes {
    return Err(InvalidCharge)
  }
  reserve_capacity(ledger, retained_bytes, execution_bytes).map(read => {
    ledger,
    reservation: read.reservation,
    capacity: execution_bytes,
    allocated: 0L,
    closing: false,
    growth: None,
  })
}

///|
pub fn allocate_shared_capacity(
  owner : SharedCapacity,
  bytes : Int64,
) -> Result[SharedAllocation, LedgerIssue] {
  match check_imported_child_admission(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_original_resources_mutable(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.closing ||
    owner.growth is Some(_) ||
    !reservation_open(owner.reservation) {
    return Err(ClosedReservation)
  }
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > owner.capacity - owner.allocated {
    return Err(RetentionLimit)
  }
  owner.allocated += bytes
  Ok({ owner, bytes, readers: 0, retiring: false, released: false, })
}

///|
pub fn borrow_shared_capacity(
  owner : SharedCapacity,
  allocation : SharedAllocation,
) -> Result[SharedBorrow, LedgerIssue] {
  match check_imported_child_admission(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(owner, allocation.owner) {
    return Err(ForeignOwner)
  }
  match check_original_resources_mutable(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.closing ||
    owner.growth is Some(_) ||
    !reservation_open(owner.reservation) ||
    allocation.retiring ||
    allocation.released {
    return Err(ClosedHolding)
  }
  if allocation.readers == 2147483647 {
    return Err(InvalidCharge)
  }
  allocation.readers += 1
  Ok({ allocation, returned: false, })
}

///|
/// A request to retire a copy forbids new readers but releases no capacity.
pub fn retire_shared_capacity(
  allocation : SharedAllocation,
) -> Result[Unit, LedgerIssue] {
  match check_original_resources_mutable(allocation.owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  allocation.retiring = true
  Ok(())
}

///|
/// Call only after the physical reader has stopped, not on cancellation request.
pub fn return_shared_capacity(
  borrow : SharedBorrow,
) -> Result[Unit, LedgerIssue] {
  let allocation = borrow.allocation
  match check_original_resources_mutable(allocation.owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if borrow.returned || allocation.readers <= 0 {
    return Err(InvalidCharge)
  }
  allocation.readers -= 1
  borrow.returned = true
  Ok(())
}

///|
/// Successful physical cleanup acknowledgement, never a logical handle close.
pub fn release_shared_capacity(
  allocation : SharedAllocation,
) -> Result[Unit, LedgerIssue] {
  match check_original_resources_mutable(allocation.owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if allocation.released {
    return Err(ClosedHolding)
  }
  if !allocation.retiring || allocation.readers != 0 {
    return Err(InvalidCharge)
  }
  if allocation.owner.growth is Some(growth) &&
    physical_equal(growth.control, allocation) {
    return Err(InvalidCharge)
  }
  allocation.owner.allocated -= allocation.bytes
  allocation.released = true
  Ok(())
}

///|
pub fn close_shared_capacity(
  owner : SharedCapacity,
) -> Result[Unit, LedgerIssue] {
  match check_original_resources_mutable(owner.ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.closing = true
  mark_cleanup_pending(owner.ledger, owner.reservation)
}

///|
/// Resource cleanup must also finish outstanding readers and retire their copies.
pub fn settle_shared_capacity(
  owner : SharedCapacity,
) -> Result[Unit, LedgerIssue] {
  if !owner.closing || owner.allocated != 0L || owner.growth is Some(_) {
    return Err(InvalidCharge)
  }
  settle_reservation(owner.ledger, owner.reservation)
}

///|
/// Exact borrower token; equal allocations do not permit duplicate returns.
struct SharedBorrow {
  allocation : SharedAllocation
  mut returned : Bool
}

///|
pub(all) struct SharedCapacityUsage {
  capacity : Int64
  allocated : Int64
  closing : Bool
}

///|
pub(all) struct SharedAllocationUsage {
  bytes : Int64
  readers : Int
  retiring : Bool
  released : Bool
}

///|
pub fn shared_capacity_usage(owner : SharedCapacity) -> SharedCapacityUsage {
  {
    capacity: owner.capacity,
    allocated: owner.allocated,
    closing: owner.closing,
  }
}

///|
pub fn shared_allocation_usage(
  allocation : SharedAllocation,
) -> SharedAllocationUsage {
  {
    bytes: allocation.bytes,
    readers: allocation.readers,
    retiring: allocation.retiring,
    released: allocation.released,
  }
}
