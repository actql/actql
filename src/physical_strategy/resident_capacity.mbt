///|
/// One run-owned DB capacity reservation. Resident table allowances are
/// suballocations of this capacity, not additional Host retained allocations.
priv struct ResidentCapacity {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  capacity : Int64
  mut allocated : Int64
  mut closing : Bool
}

///|
priv struct ResidentAllocation {
  owner : ResidentCapacity
  bytes : Int64
  mut readers : Int
  mut retiring : Bool
  mut released : Bool
}

///|
fn reserve_resident_capacity(
  ledger : @resources.Ledger,
  bytes : Int64,
) -> Result[ResidentCapacity, @resources.LedgerIssue] {
  if bytes <= 0L {
    return Err(InvalidCharge)
  }
  match @resources.reserve_attempt(ledger, 0L, 0L, bytes) {
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
fn allocate_resident_capacity(
  owner : ResidentCapacity,
  bytes : Int64,
) -> Result[ResidentAllocation, @resources.LedgerIssue] {
  if owner.closing || !@resources.reservation_open(owner.reservation) {
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
fn borrow_resident_capacity(
  owner : ResidentCapacity,
  allocation : ResidentAllocation,
) -> Result[Unit, @resources.LedgerIssue] {
  if !physical_equal(owner, allocation.owner) {
    return Err(ForeignOwner)
  }
  if owner.closing ||
    !@resources.reservation_open(owner.reservation) ||
    allocation.retiring ||
    allocation.released {
    return Err(ClosedHolding)
  }
  if allocation.readers == 2147483647 {
    return Err(InvalidCharge)
  }
  allocation.readers += 1
  Ok(())
}

///|
/// A request to retire a table forbids new readers but releases no capacity.
fn retire_resident_capacity(allocation : ResidentAllocation) -> Unit {
  allocation.retiring = true
}

///|
/// Call only after the native reader has stopped, not on cancellation request.
fn return_resident_capacity(
  allocation : ResidentAllocation,
) -> Result[Unit, @resources.LedgerIssue] {
  if allocation.readers <= 0 {
    return Err(InvalidCharge)
  }
  allocation.readers -= 1
  Ok(())
}

///|
/// Successful DROP/DB cleanup acknowledgement, never a logical handle close.
fn release_resident_capacity(
  allocation : ResidentAllocation,
) -> Result[Unit, @resources.LedgerIssue] {
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
fn close_resident_capacity(
  owner : ResidentCapacity,
) -> Result[Unit, @resources.LedgerIssue] {
  owner.closing = true
  @resources.mark_cleanup_pending(owner.ledger, owner.reservation)
}

///|
/// DB cleanup must also finish outstanding readers and retire their tables.
fn settle_resident_capacity(
  owner : ResidentCapacity,
) -> Result[Unit, @resources.LedgerIssue] {
  if !owner.closing || owner.allocated != 0L {
    return Err(InvalidCharge)
  }
  @resources.settle_reservation(owner.ledger, owner.reservation)
}
