///|
/// Byte custody on the existing Ledger, not a physical-send reservation.
/// No public conversion exposes the inner Reservation to transfer/quantity APIs.
struct CapacityReservation {
  reservation : Reservation
}

///|
/// Read only this original reservation's currently reserved retention and
/// execution. The owning consumer accounts its finite reservation set rather
/// than subtracting unrelated usage from the shared Run Ledger. Closed means
/// no remaining reservation, not release of separate holdings or physical
/// backing. This observes no current callback and admits no new resource use.
pub fn reservation_capacity_amounts(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[(Int64, Int64), LedgerIssue] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if reservation.open {
    Ok((reservation.retention, reservation.execution))
  } else {
    Ok((0L, 0L))
  }
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
  match check_original_reservation_slot(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reserve_capacity_current(ledger, retained_bytes, execution_bytes)
}

///|
// Same synchronous owner after its nonnegative input and original current/
// slot checks. Initial preparation validates pristine history in that same
// cut, without repeating those checks or this reservation allocator.
fn reserve_capacity_current(
  ledger : Ledger,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[CapacityReservation, LedgerIssue] {
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
  let retained = usage.held_bytes +
    usage.reserved_retention_bytes +
    retained_bytes
  match
    grow_imported_platform_working_current(
      ledger,
      retained,
      usage.reserved_execution_bytes + execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  ledger.usage = {
    ..usage,
    live_reservations: usage.live_reservations + 1,
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
    attempt_reserved: false,
    attempt_started: false,
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
/// Grow the SAME byte-only token before its next constructor. Delegate the
/// original/current, monotonic-byte and imported-owner checks once; never
/// expose its inner send/quantity reservation or issue another slot/attempt.
pub fn grow_capacity_reservation(
  ledger : Ledger,
  capacity : CapacityReservation,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  grow_execution_reservation_capacity(
    ledger,
    capacity.reservation,
    retained_bytes,
    execution_bytes,
  )
}

///|
// Check an exact previously admitted byte-only token without exposing its
// mutable inner reservation or creating transfer/quantity/send authority.
pub fn capacity_reservation_matches(
  ledger : Ledger,
  reservation : CapacityReservation,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  let token = reservation.reservation
  physical_equal(ledger, token.owner) &&
  token.open &&
  !token.cleanup_pending &&
  token.retention == retained_bytes &&
  token.execution == execution_bytes &&
  token.transfer == 0L &&
  token.quantities is None &&
  token.uncertain_quantities is None
}

///|
/// Read only the allowance of this original byte-only token. Aggregate free
/// capacity, another token or equal bytes on another Ledger cannot substitute
/// for it. This neither claims a new consumer nor grants any send/permission;
/// the caller still proves original custody, complete simultaneous bounds and
/// cleanup responsibility through their existing Owners.
pub fn capacity_reservation_covers(
  ledger : Ledger,
  reservation : CapacityReservation,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  let token = reservation.reservation
  retained_bytes >= 0L &&
  execution_bytes >= 0L &&
  physical_equal(ledger, token.owner) &&
  token.open &&
  !token.cleanup_pending &&
  retained_bytes <= token.retention &&
  execution_bytes <= token.execution &&
  token.transfer == 0L &&
  token.quantities is None &&
  token.uncertain_quantities is None
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

///|
/// The sole byte-vector mutation for an original byte-only capacity token. Callers
/// prove consumer-specific growth or disposal; all capacity checks occur before
/// any mutation. This is not a grant and cannot change Ledger identity.
fn resize_capacity_reservation(
  ledger : Ledger,
  capacity : CapacityReservation,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LedgerIssue] {
  let token = capacity.reservation
  if retained < 0L || execution < 0L {
    return Err(InvalidCharge)
  }
  match reservation_check(ledger, token) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  resize_capacity_reservation_current(ledger, capacity, retained, execution)
}

///|
// The same mutation after the closed original/current boundary, with no
// callback or reusable current proof between these checks and the mutation.
fn resize_capacity_reservation_current(
  ledger : Ledger,
  capacity : CapacityReservation,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LedgerIssue] {
  if retained < 0L || execution < 0L {
    return Err(InvalidCharge)
  }
  let token = capacity.reservation
  match reservation_check_current(ledger, token) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if token.transfer != 0L ||
    token.quantities is Some(_) ||
    token.uncertain_quantities is Some(_) ||
    token.cleanup_pending {
    return Err(InvalidCharge)
  }
  let retained_delta = retained - token.retention
  let execution_delta = execution - token.execution
  if (retained_delta > 0L || execution_delta > 0L) &&
    ledger.original_inventory is Some(inventory) &&
    physical_equal(inventory.bootstrap, capacity) &&
    original_inventory_preparation_owned(inventory) &&
    inventory.closing {
    return Err(ClosedReservation)
  }
  resize_reservation_bytes_current(ledger, token, retained, execution)
}

///|
// The original closed current boundary owns every caller. Share byte-vector
// arithmetic between byte-only preparation and the existing physical attempt;
// neither caller changes transfer, attempts, quantities or reservation slots.
fn resize_reservation_bytes_current(
  ledger : Ledger,
  token : Reservation,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LedgerIssue] {
  let usage = ledger.usage
  let retained_delta = retained - token.retention
  let execution_delta = execution - token.execution
  // Original stopping permits disposal, never new allocation. The preceding
  // reservation check has refreshed currentness and may have latched stopping.
  if (retained_delta > 0L || execution_delta > 0L) &&
    ledger.imported_child is Some(origin) &&
    origin.stopping {
    return Err(ClosedReservation)
  }
  if retained_delta >
    ledger.limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes {
    return Err(RetentionLimit)
  }
  if execution_delta >
    ledger.limits.execution_bytes - usage.reserved_execution_bytes {
    return Err(ExecutionLimit)
  }
  match
    grow_imported_platform_working_current(
      ledger,
      usage.held_bytes + usage.reserved_retention_bytes + retained_delta,
      usage.reserved_execution_bytes + execution_delta,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  ledger.usage = {
    ..usage,
    reserved_retention_bytes: usage.reserved_retention_bytes + retained_delta,
    reserved_execution_bytes: usage.reserved_execution_bytes + execution_delta,
    peak_retention_bytes: Int64::max(
      usage.peak_retention_bytes,
      usage.held_bytes + usage.reserved_retention_bytes + retained_delta,
    ),
  }
  token.retention = retained
  token.execution = execution
  Ok(())
}
