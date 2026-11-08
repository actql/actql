///|
/// Back the next bounded transfer on this SAME original reservation. The
/// absolute remaining allowance is idempotent; received/uncertain bytes and
/// every other live reservation still consume the original cumulative limit.
/// This neither sends, charges bytes, starts another attempt nor returns debt.
pub fn ensure_transfer_reservation_capacity(
  ledger : Ledger,
  reservation : Reservation,
  remaining : Int64,
) -> Result[Unit, LedgerIssue] {
  if remaining < 0L {
    return Err(InvalidCharge)
  }
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_imported_child_admission_current(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  if reservation.cleanup_pending ||
    reservation.completed_output is Some(_) ||
    (
      ledger.original_inventory is Some(inventory) &&
      physical_equal(inventory.bootstrap.reservation, reservation)
    ) {
    return Err(InvalidCharge)
  }
  if remaining <= reservation.transfer {
    return Ok(())
  }
  let extra = remaining - reservation.transfer
  let usage = ledger.usage
  if extra >
    ledger.limits.transfer_bytes -
    usage.transferred_bytes -
    usage.uncertain_transfer_bytes -
    usage.reserved_transfer_bytes {
    return Err(TransferLimit)
  }
  // No callback between the original/current check and this same debit.
  ledger.usage = {
    ..usage,
    reserved_transfer_bytes: usage.reserved_transfer_bytes + extra,
  }
  reservation.transfer = remaining
  Ok(())
}
