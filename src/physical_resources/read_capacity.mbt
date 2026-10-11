///|
/// Byte custody on the existing Ledger, not a physical-send reservation.
/// No public conversion exposes the inner Reservation to transfer/quantity APIs.
struct CapacityReservation {
  reservation : Reservation
}

///|
/// Admit read retention and scratch before materialization. This grants no
/// transfer, attempt or token/cost/duration allowance and restores no unknown
/// historical usage. The caller owns physical cleanup before settlement.
pub fn reserve_capacity(
  ledger : Ledger,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[CapacityReservation, LedgerIssue] {
  if retained_bytes < 0L || execution_bytes < 0L {
    return Err(InvalidCharge)
  }
  guard ledger.next_capacity_serial is Some(serial) else {
    return Err(InvalidCharge)
  }
  let usage = ledger.usage
  if retained_bytes >
    ledger.limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes {
    return Err(RetentionLimit)
  }
  if execution_bytes >
    ledger.limits.execution_bytes - usage.reserved_execution_bytes {
    return Err(ExecutionLimit)
  }
  match check_original_reservation_slot(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let retained = usage.held_bytes +
    usage.reserved_retention_bytes +
    retained_bytes
  ledger.usage = {
    ..usage,
    reserved_retention_bytes: usage.reserved_retention_bytes + retained_bytes,
    reserved_execution_bytes: usage.reserved_execution_bytes + execution_bytes,
    peak_retention_bytes: Int64::max(usage.peak_retention_bytes, retained),
  }
  ledger.next_capacity_serial = if serial == -2147483648 {
    None
  } else {
    Some(serial - 1)
  }
  let reservation : Reservation = {
    owner: ledger,
    serial,
    transfer: 0L,
    retention: retained_bytes,
    execution: execution_bytes,
    open: true,
    cleanup_pending: false,
    quantities: None,
    uncertain_quantities: None,
    observed_quantities: (false, false, false),
    completed_output: None,
  }
  record_original_reservation(ledger, reservation)
  Ok({ reservation, })
}

///|
pub fn capacity_reservation_open(reservation : CapacityReservation) -> Bool {
  reservation_open(reservation.reservation)
}

///|
/// Call only on the existing owner's confirmed physical cleanup path. A
/// cancellation request or logical read completion is not that acknowledgement.
pub fn settle_capacity(
  ledger : Ledger,
  reservation : CapacityReservation,
) -> Result[Unit, LedgerIssue] {
  settle_reservation(ledger, reservation.reservation)
}
