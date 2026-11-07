///|
// Production ports come from the fixed target-specific installed import or
// the same Owner's nominal backed-child issuer. No public constructor accepts
// callbacks, scalar quota or a permission Bool. Unsupported imports stay closed.
priv struct ImportedChildLedgerOrigin {
  nonce : Int64
  mut admit : (Int64) -> Int
  mut current : (Int64) -> Int
  mut limit : (Int64, Int) -> Int64
  mut capacity : (Int64, Int) -> Int64
  mut report : (Int64, LedgerUsage) -> Int
  mut stop : (Int64) -> Int
  fixed_capacities : Bool
  mut working : (PlatformVMWorkingCapacity, Int64, Int64)?
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
  priv mut pending_report_issue : ImportedChildLedgerIssue?
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
  fixed_capacities? : Bool = true,
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
      fixed_capacities,
      working: None,
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
    pending_report_issue: None,
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
  // The original callback can reenter this ledger and record sticky loss.
  // A later outer observation cannot restore that same funding original.
  if origin.unavailable {
    Err(ChildFundingUnavailable)
  } else {
    Ok(())
  }
}

///|
fn check_imported_child_admission(ledger : Ledger) -> Result[Unit, LedgerIssue] {
  match check_imported_child_ledger(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_imported_child_admission_current(ledger)
}

///|
// Inspect the result of the existing current fence without calling it twice.
// Cleanup and post-use accounting may continue while a new Start is refused.
fn check_imported_child_admission_current(
  ledger : Ledger,
) -> Result[Unit, LedgerIssue] {
  if ledger.imported_child is Some(origin) && origin.unavailable {
    Err(ChildFundingUnavailable)
  } else if ledger.imported_child is Some(origin) && origin.stopping {
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
  ledger.imported_child is Some(origin) &&
  origin.fixed_capacities &&
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
  ledger.usage = {
    ..ledger.usage,
    live_reservations: ledger.usage.live_reservations + 1,
  }
  let reservation : Reservation = {
    owner: ledger,
    serial,
    transfer: 0L,
    retention: 0L,
    execution: bytes,
    open: true,
    attempt_reserved: false,
    attempt_started: false,
    cleanup_pending: false,
    quantities: None,
    uncertain_quantities: None,
    observed_quantities: (false, false, false),
    completed_output: None,
  }
  {
    ledger,
    reservation,
    capacity: bytes,
    allocated: 0L,
    closing: false,
    growth: None,
  }
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
  let wasm = if port.fixed_capacities {
    (port.capacity)(port.nonce, 0)
  } else {
    0L
  }
  let host = if port.fixed_capacities {
    (port.capacity)(port.nonce, 1)
  } else {
    0L
  }
  // Negative import results are unavailable/unknown observations, never
  // negative quota or zero. The original private port owns the failed reply.
  if planning < 0L ||
    attempts < 0L ||
    holdings < 0L ||
    transfer < 0L ||
    retained < 0L ||
    execution < 0L ||
    wasm < 0L ||
    host < 0L {
    return if planning == -41L ||
      attempts == -41L ||
      holdings == -41L ||
      transfer == -41L ||
      retained == -41L ||
      execution == -41L ||
      wasm == -41L ||
      host == -41L {
      Err(Unknown)
    } else {
      Err(Unavailable)
    }
  }
  if planning < 0L ||
    planning > 2147483647L ||
    attempts < 0L ||
    attempts > 2147483647L ||
    holdings < 0L ||
    holdings > 2147483647L ||
    transfer < 0L ||
    retained < 0L ||
    execution < 0L ||
    (port.fixed_capacities && (wasm <= 0L || host <= 0L)) ||
    wasm > execution ||
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
  if port.fixed_capacities {
    ledger.usage = { ..ledger.usage, reserved_execution_bytes: wasm + host, }
    ledger.next_capacity_serial = Some(-3)
    value.wasm_capacity = Some(imported_child_seed_capacity(ledger, -1, wasm))
    value.host_capacity = Some(imported_child_seed_capacity(ledger, -2, host))
  }
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
  if !value.origin.fixed_capacities {
    return Err(Unavailable)
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
/// Trusted same-parent physical assembly only. This branch seeds no VM/Host
/// capacities: its first reservation must be the original funded bootstrap.
/// It is not a fresh root, numerical profile, physical allocation or grant.
pub fn take_imported_original_child_ledger(
  value : ImportedChildLedger,
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.origin.fixed_capacities {
    return Err(Unavailable)
  }
  if value.taken || value.origin.stopping {
    return Err(AlreadyConsumed)
  }
  guard value.ledger is Some(ledger) else { return Err(Unavailable) }
  match check_imported_child_admission(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.taken = true
  Ok(ledger)
}

///|
/// Same taken original child and its exact accounting view, without issuing,
/// taking, reporting or reserving anything. A scalar/fresh/sibling Ledger is
/// not a replacement for this import's live physical-owner correspondence.
pub fn check_imported_original_child_ledger(
  value : ImportedChildLedger,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.origin.fixed_capacities || !value.taken || value.origin.stopping {
    return Err(Unavailable)
  }
  guard value.ledger is Some(original) &&
    physical_equal(original, ledger) &&
    ledger.imported_child is Some(origin) &&
    physical_equal(origin, value.origin) else {
    return Err(ForeignOriginal)
  }
  match check_imported_child_admission(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  check_imported_original_child_ledger_current(value, ledger)
}

///|
// The same tuple after this owner's current boundary. The closed managed
// operation uses it after its non-escaping Local original check too.
fn check_imported_original_child_ledger_current(
  value : ImportedChildLedger,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  // Keep the post-callback original tuple fence local to this owner. The
  // callback can synchronously retire/change a child while returning current.
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.taken &&
    !value.origin.fixed_capacities &&
    value.ledger is Some(original) &&
    physical_equal(original, ledger) &&
    ledger.imported_child is Some(origin) &&
    physical_equal(origin, value.origin) &&
    origin.ledger is Some(bound) &&
    physical_equal(bound, ledger) else {
    return Err(ForeignOriginal)
  }
  check_imported_child_admission_current(ledger).map_err(issue => {
    Resource(issue)
  })
}

///|
/// Validate the already taken original VM capacity without returning another
/// Ledger, reserving bytes, or issuing physical/read/launch authority.
pub fn require_imported_child_vm_capacity(
  value : ImportedChildLedger,
  ledger : Ledger,
  capacity : SharedCapacity,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !value.taken {
    return Err(Unavailable)
  }
  guard value.ledger is Some(original) &&
    physical_equal(original, ledger) &&
    value.wasm_capacity is Some(vm) &&
    physical_equal(vm, capacity) else {
    return Err(ForeignOriginal)
  }
  check_imported_child_admission(ledger).map_err(issue => Resource(issue))
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
    return match value.pending_report_issue {
      Some(issue) => Err(issue)
      None => Err(Unknown)
    }
  }
  guard value.ledger is Some(ledger) else { return Err(Unavailable) }
  let usage = ledger_usage(ledger)
  value.pending_report = Some(usage)
  let port = value.origin
  match imported_child_status((port.report)(port.nonce, usage)) {
    Err(issue) => {
      value.pending_report_issue = Some(issue)
      return Err(issue)
    }
    Ok(_) => ()
  }
  value.pending_report = None
  value.pending_report_issue = None
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

///|
/// Cleanup DATA only. The trusted physical caller must already be outside all
/// child allocation scopes in its supplied outer control lifetime. Preserve
/// the same Ledger and every charge; old escaped snapshots remain live aliases.
/// This does not retire an allocation, report usage or acknowledge an Owner.
pub fn relocate_imported_child_cleanup_usage(
  value : ImportedChildLedger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.pending_report is Some(_) {
    return Err(value.pending_report_issue.unwrap_or(Unknown))
  }
  if !value.attempted ||
    !value.taken ||
    !value.stop_attempted ||
    !value.origin.stopping {
    return Err(Unavailable)
  }
  if value.stop_outcome is Some(issue) {
    return Err(issue)
  }
  guard value.ledger is Some(ledger) &&
    ledger.imported_child is Some(origin) &&
    physical_equal(origin, value.origin) &&
    origin.ledger is Some(original) &&
    physical_equal(original, ledger) else {
    return Err(ForeignOriginal)
  }
  match check_imported_child_ledger(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let usage = ledger.usage
  let copied_usage : LedgerUsage = {
    planning_work: usage.planning_work,
    attempts: usage.attempts,
    reserved_attempts: usage.reserved_attempts,
    holdings: usage.holdings,
    live_reservations: usage.live_reservations,
    live_delegations: usage.live_delegations,
    transferred_bytes: usage.transferred_bytes,
    uncertain_transfer_bytes: usage.uncertain_transfer_bytes,
    reserved_transfer_bytes: usage.reserved_transfer_bytes,
    held_bytes: usage.held_bytes,
    reserved_retention_bytes: usage.reserved_retention_bytes,
    reserved_execution_bytes: usage.reserved_execution_bytes,
    peak_retention_bytes: usage.peak_retention_bytes,
  }
  let quantities = ledger.quantity_usage
  let copied_quantities : QuantityUsage = {
    reserved: cleanup_quantity_copy(quantities.reserved),
    uncertain: cleanup_quantity_copy(quantities.uncertain),
    consumed: cleanup_quantity_copy(quantities.consumed),
  }
  let copied_limits = ledger.quantity_limits.map(cleanup_quantity_copy)
  // Construct every replacement before mutating the same original controls.
  ledger.usage = copied_usage
  ledger.quantity_usage = copied_quantities
  ledger.quantity_limits = copied_limits
  Ok(())
}

///|
fn cleanup_quantity_copy(value : QuantityAmounts) -> QuantityAmounts {
  {
    tokens: value.tokens,
    cost_units: value.cost_units,
    duration_ms: value.duration_ms,
  }
}

///|
/// Callback-free retention fence for an already taken original frame/Ledger.
/// This observes only local ownership, stop and park state. It performs no
/// external current observation and grants no read, allocation or physical
/// authority. The enclosing operation must observe its actual supplier first.
pub fn check_imported_original_child_ledger_retained(
  value : ImportedChildLedger,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_imported_original_child_ledger_current(value, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_original_resources_mutable_current(ledger).map_err(issue => {
    Resource(issue)
  })
}
