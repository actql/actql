///|
// Only the fixed target-specific installed import supplies these ports in
// production. No public constructor accepts callbacks, DATA or a permission Bool.
// Unsupported targets construct no fake physical port.
priv struct ImportedChildLedgerOrigin {
  nonce : Int64
  admit : (Int64) -> Int
  current : (Int64) -> Int
  limit : (Int64, Int) -> Int64
  capacity : (Int64, Int) -> Int64
  report : (Int64, LedgerUsage) -> Int
  stop : (Int64) -> Int
  // The back-reference rejects copies without another Resource Owner.
  mut ledger : Ledger?
  mut stopping : Bool
  mut unavailable : Bool
}

///|
/// Partial original custody survives admit/current/report failure. These
/// records, port closures, snapshots and seeded tokens require the trusted
/// original pre-bootstrap envelope; this API supplies no numerical policy.
pub struct ImportedChildLedger {
  priv mut original : ImportedChildLedger?
  priv origin : ImportedChildLedgerOrigin
  priv mut attempted : Bool
  priv mut taken : Bool
  priv mut ledger : Ledger?
  priv mut wasm_capacity : SharedCapacity?
  priv mut host_capacity : SharedCapacity?
  priv mut pending_report : LedgerUsage?
  priv mut stop_attempted : Bool
  priv mut stop_outcome : ImportedChildLedgerIssue?
}

///|
pub(all) enum ImportedChildLedgerIssue {
  Unavailable
  Unknown
  ForeignOriginal
  AlreadyConsumed
  InvalidOriginal
  Resource(LedgerIssue)
} derive(Eq, Debug)

///|
fn imported_child_status(code : Int) -> Result[Unit, ImportedChildLedgerIssue] {
  if code == 0 {
    Ok(())
  } else if code == -41 {
    Err(Unknown)
  } else {
    Err(Unavailable)
  }
}

///|
fn prepare_imported_child_port(
  nonce : Int64,
  admit : (Int64) -> Int,
  current : (Int64) -> Int,
  limit : (Int64, Int) -> Int64,
  capacity : (Int64, Int) -> Int64,
  report : (Int64, LedgerUsage) -> Int,
  stop : (Int64) -> Int,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  if nonce <= 0L {
    return Err(InvalidOriginal)
  }
  let value : ImportedChildLedger = {
    original: None,
    origin: {
      nonce,
      admit,
      current,
      limit,
      capacity,
      report,
      stop,
      ledger: None,
      stopping: false,
      unavailable: false,
    },
    attempted: false,
    taken: false,
    ledger: None,
    wasm_capacity: None,
    host_capacity: None,
    pending_report: None,
    stop_attempted: false,
    stop_outcome: None,
  }
  value.original = Some(value)
  Ok(value)
}

///|
/// Fixed installed Host imports only. Unsupported targets refuse rather than
/// interpreting scalar limits as an original funding observation.
pub fn prepare_imported_child_ledger(
  nonce : Int64,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  if nonce <= 0L {
    return Err(InvalidOriginal)
  }
  match imported_child_port(nonce) {
    Err(issue) => Err(issue)
    Ok((admit, current, limit, capacity, report, stop)) =>
      prepare_imported_child_port(
        nonce, admit, current, limit, capacity, report, stop,
      )
  }
}

///|
fn imported_child_original(
  value : ImportedChildLedger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  if value.original is Some(original) && physical_equal(original, value) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
fn check_imported_child_ledger(ledger : Ledger) -> Result[Unit, LedgerIssue] {
  guard ledger.imported_child is Some(origin) else { return Ok(()) }
  if !(origin.ledger is Some(original) && physical_equal(original, ledger)) {
    return Err(ForeignOwner)
  }
  if origin.unavailable {
    return Err(ChildFundingUnavailable)
  }
  match (origin.current)(origin.nonce) {
    0 => ()
    1 => origin.stopping = true
    _ => {
      origin.unavailable = true
      return Err(ChildFundingUnavailable)
    }
  }
  Ok(())
}

///|
fn check_imported_child_admission(ledger : Ledger) -> Result[Unit, LedgerIssue] {
  match check_imported_child_ledger(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if ledger.imported_child is Some(origin) && origin.stopping {
    Err(ClosedReservation)
  } else {
    Ok(())
  }
}

///|
// Restriction only: these disjoint negative serials were seeded by this exact
// imported owner, not issued as new attempts. VM/Host physical lifetime cannot
// end inside a still-running child VM. Only the parent settles after real ACK.
fn imported_child_fixed_capacity(
  ledger : Ledger,
  reservation : Reservation,
) -> Bool {
  ledger.imported_child is Some(_) &&
  physical_equal(ledger, reservation.owner) &&
  (reservation.serial == -1 || reservation.serial == -2)
}

///|
// Project already funded VM/Host execution into the existing reservation
// domains. No attempt is consumed, physical allocation begun or parent bytes
// reserved again. These two negative serials cannot be reused by later reads.
fn imported_child_seed_capacity(
  ledger : Ledger,
  serial : Int,
  bytes : Int64,
) -> SharedCapacity {
  let reservation : Reservation = {
    owner: ledger,
    serial,
    transfer: 0L,
    retention: 0L,
    execution: bytes,
    open: true,
    cleanup_pending: false,
    quantities: None,
    uncertain_quantities: None,
    observed_quantities: (false, false, false),
    completed_output: None,
  }
  { ledger, reservation, capacity: bytes, allocated: 0L, closing: false, }
}

///|
/// One actual Host-import admission. A failed/lost reply never retries admit
/// or reconstructs a root from limits. The same partial carrier remains owned.
pub fn start_imported_child_ledger(
  value : ImportedChildLedger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.attempted || value.origin.stopping {
    return Err(AlreadyConsumed)
  }
  value.attempted = true
  let port = value.origin
  match imported_child_status((port.admit)(port.nonce)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match imported_child_status((port.current)(port.nonce)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let planning = (port.limit)(port.nonce, 0)
  let attempts = (port.limit)(port.nonce, 1)
  let holdings = (port.limit)(port.nonce, 2)
  let transfer = (port.limit)(port.nonce, 3)
  let retained = (port.limit)(port.nonce, 4)
  let execution = (port.limit)(port.nonce, 5)
  let wasm = (port.capacity)(port.nonce, 0)
  let host = (port.capacity)(port.nonce, 1)
  if planning < 0L ||
    planning > 2147483647L ||
    attempts < 0L ||
    attempts > 2147483647L ||
    holdings < 0L ||
    holdings > 2147483647L ||
    transfer < 0L ||
    retained < 0L ||
    execution < 0L ||
    wasm <= 0L ||
    wasm > execution ||
    host <= 0L ||
    host > execution - wasm {
    return Err(InvalidOriginal)
  }
  // Recheck the SAME installed import after acquiring the whole bounded DATA.
  match imported_child_status((port.current)(port.nonce)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let ledger = match
    create_ledger({
      planning_work: planning.to_int(),
      attempts: attempts.to_int(),
      holdings: holdings.to_int(),
      transfer_bytes: transfer,
      retained_bytes: retained,
      execution_bytes: execution,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  ledger.imported_child = Some(value.origin)
  value.origin.ledger = Some(ledger)
  ledger.usage = { ..ledger.usage, reserved_execution_bytes: wasm + host, }
  ledger.next_capacity_serial = Some(-3)
  value.wasm_capacity = Some(imported_child_seed_capacity(ledger, -1, wasm))
  value.host_capacity = Some(imported_child_seed_capacity(ledger, -2, host))
  value.ledger = Some(ledger)
  Ok(())
}

///|
/// Existing Root assembly only. No packet/CID/scalar limits enter this take.
/// Its original carrier remains retained for reporting and logical stop.
pub fn take_imported_child_ledger(
  value : ImportedChildLedger,
) -> Result[(Ledger, SharedCapacity, SharedCapacity), ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.taken || value.origin.stopping {
    return Err(AlreadyConsumed)
  }
  guard value.ledger is Some(ledger) &&
    value.wasm_capacity is Some(wasm) &&
    value.host_capacity is Some(host) else {
    return Err(Unavailable)
  }
  match check_imported_child_admission(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.taken = true
  Ok((ledger, wasm, host))
}

///|
/// Report this original Ledger's actual snapshot, never caller-supplied usage.
/// ACK loss retains the immutable snapshot and prevents blind report retries.
pub fn report_imported_child_ledger(
  value : ImportedChildLedger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.pending_report is Some(_) {
    return Err(Unknown)
  }
  guard value.ledger is Some(ledger) else { return Err(Unavailable) }
  let usage = ledger_usage(ledger)
  value.pending_report = Some(usage)
  let port = value.origin
  match imported_child_status((port.report)(port.nonce, usage)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  value.pending_report = None
  Ok(())
}

///|
/// Logical stop only. Original cleanup/accounting remains possible while the
/// same physical import is lifetime-current. No capacity or parent quota is
/// returned and no VM/FD/reader/Store retirement is acknowledged.
pub fn stop_imported_child_ledger(
  value : ImportedChildLedger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.stop_attempted {
    return match value.stop_outcome {
      Some(issue) => Err(issue)
      None => Ok(())
    }
  }
  value.origin.stopping = true
  value.stop_attempted = true
  let port = value.origin
  match imported_child_status((port.stop)(port.nonce)) {
    Ok(_) => Ok(())
    Err(issue) => {
      value.stop_outcome = Some(issue)
      Err(issue)
    }
  }
}
