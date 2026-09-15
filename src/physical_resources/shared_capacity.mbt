///|
/// One owned execution-resource reservation. Retained copy allowances are
/// suballocations of this capacity, not additional Host retained allocations.
struct SharedCapacity {
  ledger : Ledger
  reservation : Reservation
  capacity : Int64
  mut allocated : Int64
  mut closing : Bool
}

///|
struct SharedAllocation {
  owner : SharedCapacity
  bytes : Int64
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
      })
  }
}

///|
pub fn allocate_shared_capacity(
  owner : SharedCapacity,
  bytes : Int64,
) -> Result[SharedAllocation, LedgerIssue] {
  if owner.closing || !reservation_open(owner.reservation) {
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
  if !physical_equal(owner, allocation.owner) {
    return Err(ForeignOwner)
  }
  if owner.closing ||
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
pub fn retire_shared_capacity(allocation : SharedAllocation) -> Unit {
  allocation.retiring = true
}

///|
/// Call only after the physical reader has stopped, not on cancellation request.
pub fn return_shared_capacity(
  borrow : SharedBorrow,
) -> Result[Unit, LedgerIssue] {
  let allocation = borrow.allocation
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
  if allocation.released {
    return Err(ClosedHolding)
  }
  if !allocation.retiring || allocation.readers != 0 {
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
  owner.closing = true
  mark_cleanup_pending(owner.ledger, owner.reservation)
}

///|
/// Resource cleanup must also finish outstanding readers and retire their copies.
pub fn settle_shared_capacity(
  owner : SharedCapacity,
) -> Result[Unit, LedgerIssue] {
  if !owner.closing || owner.allocated != 0L {
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
