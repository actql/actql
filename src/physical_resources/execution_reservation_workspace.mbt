///|
/// Grow only byte backing of the SAME physical reservation before its next
/// constructor. The original consumer supplies the complete simultaneous
/// extent. No attempt, transfer, quantity, slot or cleanup duty is reissued.
pub fn grow_execution_reservation_capacity(
  ledger : Ledger,
  reservation : Reservation,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LedgerIssue] {
  if retained < 0L || execution < 0L {
    return Err(InvalidCharge)
  }
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  if reservation.cleanup_pending ||
    retained < reservation.retention ||
    execution < reservation.execution ||
    (
      ledger.original_inventory is Some(inventory) &&
      physical_equal(inventory.bootstrap.reservation, reservation)
    ) {
    return Err(InvalidCharge)
  }
  resize_reservation_bytes_current(ledger, reservation, retained, execution)
}

///|
/// Reduce only the execution-byte remainder of this original reservation.
/// The caller must already have retired the workspace being returned. This
/// does not acknowledge physical cleanup, close the reservation, return an
/// attempt, or change transfer, retention, quantities and consumed history.
/// An absolute remainder makes repeating the same return idempotent.
pub fn reduce_execution_reservation(
  ledger : Ledger,
  reservation : Reservation,
  remaining_execution : Int64,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Inspect restrictions after the same original current callback: it may
  // close the reservation or change its imported owner's current policy.
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  if ledger.original_inventory is Some(inventory) &&
    physical_equal(inventory.bootstrap.reservation, reservation) {
    return Err(InvalidCharge)
  }
  if remaining_execution < 0L || remaining_execution > reservation.execution {
    return Err(InvalidCharge)
  }
  ledger.usage = {
    ..ledger.usage,
    reserved_execution_bytes: ledger.usage.reserved_execution_bytes -
    reservation.execution +
    remaining_execution,
  }
  reservation.execution = remaining_execution
  Ok(())
}
