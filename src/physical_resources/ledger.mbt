///|
/// Host-private physical capacity, independent of connectors, DAGs and logical budgets.
pub(all) struct LedgerLimits {
  planning_work : Int
  attempts : Int
  holdings : Int
  transfer_bytes : Int64
  retained_bytes : Int64
  execution_bytes : Int64
} derive(Eq, Debug)

///|
pub(all) struct LedgerUsage {
  planning_work : Int
  attempts : Int
  reserved_attempts : Int
  holdings : Int
  live_reservations : Int
  live_delegations : Int
  transferred_bytes : Int64
  uncertain_transfer_bytes : Int64
  reserved_transfer_bytes : Int64
  held_bytes : Int64
  reserved_retention_bytes : Int64
  reserved_execution_bytes : Int64
  peak_retention_bytes : Int64
} derive(Eq, Debug)

///|
struct Ledger {
  limits : LedgerLimits
  mut usage : LedgerUsage
  mut next_attempt_serial : Int?
  mut next_holding_serial : Int?
  mut delegated_planning : Int
  mut delegated_attempts : Int
  mut delegated_holdings : Int
  mut quantity_limits : QuantityAmounts?
  mut quantity_usage : QuantityUsage
  // Capacity-only reads use disjoint identities without consuming send attempts.
  // None is exhausted; a settled identity is never made available again.
  mut next_capacity_serial : Int?
  // Private opt-in census belongs to this Ledger. Its independently derived
  // control envelope must be funded before registration; no ordinary caller
  // enables it, and it is not a separate accounting owner.
  mut original_inventory : LedgerOriginalInventory?
  // Also resident on ordinary Ledgers. The existing installed envelope must
  // cover this reference and any live imported-child controls before use.
  mut imported_child : ImportedChildLedgerOrigin?
  // One restoration of cumulative DATA into this pristine admitted Ledger.
  // Even an all-zero continuation consumes this private initialization slot.
  mut continuation_restored : Bool
}

///|
struct Reservation {
  owner : Ledger
  serial : Int
  mut transfer : Int64
  mut retention : Int64
  mut execution : Int64
  mut open : Bool
  mut attempt_reserved : Bool
  mut attempt_started : Bool
  mut cleanup_pending : Bool
  mut quantities : QuantityAmounts?
  mut uncertain_quantities : QuantityAmounts?
  mut observed_quantities : (Bool, Bool, Bool)
  mut completed_output : (Int?, Int64, Int64)?
}

///|
/// A holding is one physical allocation, never a content-identity cache entry.
struct Holding {
  owner : Ledger
  serial : Int
  reservation_serial : Int
  bytes : Int64
  mut live : Bool
}

///|
pub(all) enum LedgerIssue {
  InvalidLimits
  PlanningLimit
  AttemptLimit
  HoldingLimit
  TransferLimit
  RetentionLimit
  ExecutionLimit
  ForeignOwner
  ClosedReservation
  ClosedHolding
  InvalidCharge
  IdentityOverflow
  TokenLimit
  CostLimit
  DurationLimit
  ResourceParked
  ChildFundingUnavailable
} derive(Eq, Debug)

///|
// One immutable initial DATA value owned beside the full LedgerUsage shape.
// Equality with this value detects a report, never a pristine Ledger/identity.
let initial_ledger_usage : LedgerUsage = {
  planning_work: 0,
  attempts: 0,
  reserved_attempts: 0,
  holdings: 0,
  live_reservations: 0,
  live_delegations: 0,
  transferred_bytes: 0L,
  uncertain_transfer_bytes: 0L,
  reserved_transfer_bytes: 0L,
  held_bytes: 0L,
  reserved_retention_bytes: 0L,
  reserved_execution_bytes: 0L,
  peak_retention_bytes: 0L,
}

///|
pub fn create_ledger(limits : LedgerLimits) -> Result[Ledger, LedgerIssue] {
  if limits.planning_work < 0 ||
    limits.attempts < 0 ||
    limits.holdings < 0 ||
    limits.transfer_bytes < 0L ||
    limits.retained_bytes < 0L ||
    limits.execution_bytes < 0L {
    return Err(InvalidLimits)
  }
  Ok({
    limits,
    next_attempt_serial: Some(0),
    next_holding_serial: Some(0),
    delegated_planning: 0,
    delegated_attempts: 0,
    delegated_holdings: 0,
    quantity_limits: None,
    next_capacity_serial: Some(-1),
    original_inventory: None,
    imported_child: None,
    continuation_restored: false,
    quantity_usage: {
      reserved: zero_quantities(),
      uncertain: zero_quantities(),
      consumed: zero_quantities(),
    },
    usage: initial_ledger_usage,
  })
}

///|
pub fn ledger_usage(ledger : Ledger) -> LedgerUsage {
  ledger.usage
}

///|
pub fn charge_planning(
  ledger : Ledger,
  work : Int,
) -> Result[Unit, LedgerIssue] {
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if work < 0 {
    return Err(InvalidCharge)
  }
  if work >
    ledger.limits.planning_work -
    ledger.usage.planning_work -
    ledger.delegated_planning {
    return Err(PlanningLimit)
  }
  ledger.usage = {
    ..ledger.usage,
    planning_work: ledger.usage.planning_work + work,
  }
  record_original_prefix_work(ledger, work)
  Ok(())
}

///|
/// Atomic capacity reservation before any realization-specific work begins.
/// A failed reservation has no charge; an admitted attempt serial is never reused.
pub fn reserve_attempt(
  ledger : Ledger,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  quantities? : QuantityAmounts? = None,
) -> Result[Reservation, LedgerIssue] {
  if transfer_bytes < 0L || retained_bytes < 0L || execution_bytes < 0L {
    return Err(InvalidCharge)
  }
  match check_original_reservation_slot(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reserve_attempt_current(
    ledger, transfer_bytes, retained_bytes, execution_bytes, quantities,
  )
}

///|
// The existing reservation mutation after a trusted current observation.
// Delegation uses this same path without another reentrant callback between
// validating its quota and committing the provisioning reservation.
fn reserve_attempt_current(
  ledger : Ledger,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  quantities : QuantityAmounts?,
  preparation_input? : Bool = false,
) -> Result[Reservation, LedgerIssue] {
  match check_original_reservation_slot_current(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let u = ledger.usage
  if u.reserved_attempts >=
    ledger.limits.attempts - u.attempts - ledger.delegated_attempts {
    return Err(AttemptLimit)
  }
  if transfer_bytes >
    ledger.limits.transfer_bytes -
    u.transferred_bytes -
    u.uncertain_transfer_bytes -
    u.reserved_transfer_bytes {
    return Err(TransferLimit)
  }
  if retained_bytes >
    ledger.limits.retained_bytes - u.held_bytes - u.reserved_retention_bytes {
    return Err(RetentionLimit)
  }
  if execution_bytes >
    ledger.limits.execution_bytes - u.reserved_execution_bytes {
    return Err(ExecutionLimit)
  }
  match check_quantity_reservation(ledger, quantities) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard ledger.next_attempt_serial is Some(serial) else {
    return Err(IdentityOverflow)
  }
  let retained = u.held_bytes + u.reserved_retention_bytes + retained_bytes
  match
    grow_imported_platform_working_current(
      ledger,
      retained,
      u.reserved_execution_bytes + execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  ledger.usage = {
    ..u,
    reserved_attempts: u.reserved_attempts + 1,
    live_reservations: u.live_reservations + 1,
    reserved_transfer_bytes: u.reserved_transfer_bytes + transfer_bytes,
    reserved_retention_bytes: u.reserved_retention_bytes + retained_bytes,
    reserved_execution_bytes: u.reserved_execution_bytes + execution_bytes,
    peak_retention_bytes: if retained > u.peak_retention_bytes {
      retained
    } else {
      u.peak_retention_bytes
    },
  }
  if quantities is Some(amount) {
    ledger.quantity_usage = {
      ..ledger.quantity_usage,
      reserved: add_quantities(ledger.quantity_usage.reserved, amount),
    }
  }
  ledger.next_attempt_serial = if serial == 2147483647 {
    None
  } else {
    Some(serial + 1)
  }
  let reservation : Reservation = {
    owner: ledger,
    serial,
    transfer: transfer_bytes,
    retention: retained_bytes,
    execution: execution_bytes,
    open: true,
    attempt_reserved: true,
    attempt_started: false,
    cleanup_pending: false,
    quantities,
    uncertain_quantities: None,
    observed_quantities: (false, false, false),
    completed_output: None,
  }
  record_original_reservation(ledger, reservation, preparation_input~)
  Ok(reservation)
}

///|
fn reservation_check(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reservation_check_current(ledger, reservation)
}

///|
// SAME synchronous boundary after its original current callback. This private
// DATA/lifetime check creates no reusable proof and invokes no external port.
fn reservation_check_current(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  check_original_resources_mutable_current(ledger)
}

///|
/// Account the original trusted operation's possible physical use once. This
/// neither dispatches nor grants permission. A lost outcome never refunds it.
pub fn consume_reserved_attempt(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_imported_child_admission_current(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  consume_reserved_attempt_current(ledger, reservation)
}

///|
// Core mutation after the existing current fence. Never call another external
// current callback between validating a debit and applying that same debit.
fn consume_reserved_attempt_current(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  if reservation.attempt_started {
    return Ok(())
  }
  if !reservation.attempt_reserved {
    return Err(InvalidCharge)
  }
  ledger.usage = {
    ..ledger.usage,
    attempts: ledger.usage.attempts + 1,
    reserved_attempts: ledger.usage.reserved_attempts - 1,
  }
  reservation.attempt_reserved = false
  reservation.attempt_started = true
  Ok(())
}

///|
fn return_unused_attempt(ledger : Ledger, reservation : Reservation) -> Unit {
  if reservation.attempt_reserved {
    ledger.usage = {
      ..ledger.usage,
      reserved_attempts: ledger.usage.reserved_attempts - 1,
    }
    reservation.attempt_reserved = false
  }
}

///|
/// Charge the exact selected representation before send/accept. Even failure
/// after this boundary does not refund the transfer. No estimate is accepted.
pub fn charge_transfer(
  ledger : Ledger,
  reservation : Reservation,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  charge_transfer_current(ledger, reservation, bytes)
}

///|
fn charge_transfer_current(
  ledger : Ledger,
  reservation : Reservation,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  if reservation.completed_output is Some(_) {
    return Err(ClosedReservation)
  }
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > reservation.transfer {
    return Err(TransferLimit)
  }
  if bytes > 0L {
    match consume_reserved_attempt_current(ledger, reservation) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  reservation.transfer -= bytes
  let u = ledger.usage
  ledger.usage = {
    ..u,
    transferred_bytes: u.transferred_bytes + bytes,
    reserved_transfer_bytes: u.reserved_transfer_bytes - bytes,
  }
  Ok(())
}

///|
/// A dispatched operation has no confirmed byte observation. Preserve its
/// reserved upper bound as uncertain usage even after physical cleanup. This
/// is not an exact transfer charge or evidence that no request was sent.
pub fn mark_transfer_uncertain(
  ledger : Ledger,
  reservation : Reservation,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if reservation.completed_output is Some(_) {
    return Err(ClosedReservation)
  }
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > reservation.transfer {
    return Err(TransferLimit)
  }
  match consume_reserved_attempt_current(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reservation.transfer -= bytes
  let usage = ledger.usage
  ledger.usage = {
    ..usage,
    uncertain_transfer_bytes: usage.uncertain_transfer_bytes + bytes,
    reserved_transfer_bytes: usage.reserved_transfer_bytes - bytes,
  }
  Ok(())
}

///|
/// Commit reserved capacity to one retained allocation before exposing it.
/// Copying its handle does not allocate a new buffer or create a second charge.
pub fn retain_allocation(
  ledger : Ledger,
  reservation : Reservation,
  bytes : Int64,
) -> Result[Holding, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if reservation.completed_output is Some(_) {
    return Err(ClosedReservation)
  }
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > reservation.retention {
    return Err(RetentionLimit)
  }
  let u = ledger.usage
  if u.holdings >= ledger.limits.holdings - ledger.delegated_holdings {
    return Err(HoldingLimit)
  }
  match check_original_holding_slot(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard ledger.next_holding_serial is Some(serial) else {
    return Err(IdentityOverflow)
  }
  reservation.retention -= bytes
  ledger.usage = {
    ..u,
    holdings: u.holdings + 1,
    reserved_retention_bytes: u.reserved_retention_bytes - bytes,
    held_bytes: u.held_bytes + bytes,
  }
  ledger.next_holding_serial = if serial == 2147483647 {
    None
  } else {
    Some(serial + 1)
  }
  let holding : Holding = {
    owner: ledger,
    serial,
    reservation_serial: reservation.serial,
    bytes,
    live: true,
  }
  record_original_holding(ledger, holding)
  Ok(holding)
}

///|
/// Confirm an admitted output holding before publication. Refund only unused
/// capacity; keep independently retained allocations and consumed/uncertain
/// usage intact. Remaining execution is unreclaimed scratch, not compute work.
/// An identical notification is idempotent, including after final cleanup.
pub fn settle_completed_output_reservation(
  ledger : Ledger,
  reservation : Reservation,
  holding : Holding?,
  output_bytes : Int64,
  remaining_execution : Int64,
) -> Result[Unit, LedgerIssue] {
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if output_bytes < 0L || remaining_execution < 0L {
    return Err(InvalidCharge)
  }
  let identity = match holding {
    Some(value) => {
      if !physical_equal(ledger, value.owner) {
        return Err(ForeignOwner)
      }
      if value.reservation_serial != reservation.serial ||
        value.bytes != output_bytes {
        return Err(InvalidCharge)
      }
      Some(value.serial)
    }
    None => {
      if output_bytes != 0L {
        return Err(InvalidCharge)
      }
      None
    }
  }
  let notification = (identity, output_bytes, remaining_execution)
  if reservation.completed_output is Some(previous) {
    return if previous == notification { Ok(()) } else { Err(InvalidCharge) }
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Currentness can synchronously complete this same original. The first
  // immutable notification wins, including an identical final completion;
  // never overwrite its pending scratch or reject it merely because it closed.
  if reservation.completed_output is Some(previous) {
    return if previous == notification { Ok(()) } else { Err(InvalidCharge) }
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  if remaining_execution > reservation.execution ||
    (holding is Some(value) && !value.live) {
    return Err(InvalidCharge)
  }
  let usage = ledger.usage
  ledger.usage = {
    ..usage,
    reserved_transfer_bytes: usage.reserved_transfer_bytes -
    reservation.transfer,
    reserved_retention_bytes: usage.reserved_retention_bytes -
    reservation.retention,
    reserved_execution_bytes: usage.reserved_execution_bytes -
    reservation.execution +
    remaining_execution,
  }
  if reservation.quantities is Some(amount) {
    ledger.quantity_usage = {
      ..ledger.quantity_usage,
      reserved: subtract_quantities(ledger.quantity_usage.reserved, amount),
    }
    reservation.quantities = None
  }
  reservation.transfer = 0L
  reservation.retention = 0L
  reservation.execution = remaining_execution
  reservation.cleanup_pending = remaining_execution > 0L
  reservation.completed_output = Some(notification)
  reservation.open = remaining_execution > 0L
  if !reservation.open {
    return_unused_attempt(ledger, reservation)
    ledger.usage = {
      ..ledger.usage,
      live_reservations: ledger.usage.live_reservations - 1,
    }
    retire_original_reservation(ledger, reservation)
  }
  Ok(())
}

///|
pub fn mark_cleanup_pending(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reservation.cleanup_pending = true
  Ok(())
}

///|
pub fn reservation_pending(reservation : Reservation) -> Bool {
  reservation.open && reservation.cleanup_pending
}

///|
/// Native resources have settled, but provisional/result buffers may remain.
/// Keep retention reserved until completion or explicit failed-buffer disposal.
pub fn settle_execution_reservation(
  ledger : Ledger,
  reservation : Reservation,
  remaining_execution? : Int64 = 0L,
) -> Result[Unit, LedgerIssue] {
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if remaining_execution < 0L || remaining_execution > reservation.execution {
    return Err(InvalidCharge)
  }
  ledger.usage = {
    ..ledger.usage,
    reserved_transfer_bytes: ledger.usage.reserved_transfer_bytes -
    reservation.transfer,
    reserved_execution_bytes: ledger.usage.reserved_execution_bytes -
    reservation.execution +
    remaining_execution,
  }
  reservation.transfer = 0L
  reservation.execution = remaining_execution
  reservation.cleanup_pending = false
  Ok(())
}

///|
/// Trusted cleanup acknowledgement, not a cancellation-request callback.
/// Consumed transfer and independently retained allocations remain accounted.
pub fn settle_reservation(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  settle_reservation_current(ledger, reservation)
}

///|
fn settle_reservation_current(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  if !reservation.open {
    return Err(ClosedReservation)
  }
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  if ledger.original_inventory is Some(inventory) &&
    physical_equal(inventory.bootstrap.reservation, reservation) {
    // Only final original-Run cleanup may retire the funded census itself.
    return Err(InvalidCharge)
  }
  let u = ledger.usage
  ledger.usage = {
    ..u,
    reserved_transfer_bytes: u.reserved_transfer_bytes - reservation.transfer,
    reserved_retention_bytes: u.reserved_retention_bytes - reservation.retention,
    reserved_execution_bytes: u.reserved_execution_bytes - reservation.execution,
  }
  if reservation.quantities is Some(amount) {
    ledger.quantity_usage = {
      ..ledger.quantity_usage,
      reserved: subtract_quantities(ledger.quantity_usage.reserved, amount),
    }
    reservation.quantities = None
  }
  reservation.open = false
  return_unused_attempt(ledger, reservation)
  ledger.usage = {
    ..ledger.usage,
    live_reservations: ledger.usage.live_reservations - 1,
  }
  retire_original_reservation(ledger, reservation)
  Ok(())
}

///|
/// Host calls only when no retained result/consumer needs this exact allocation.
/// Releasing a table view alone is not that confirmation.
pub fn release_allocation(
  ledger : Ledger,
  holding : Holding,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, holding.owner) {
    return Err(ForeignOwner)
  }
  if !holding.live {
    return Err(ClosedHolding)
  }
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !holding.live {
    return Err(ClosedHolding)
  }
  ledger.usage = {
    ..ledger.usage,
    held_bytes: ledger.usage.held_bytes - holding.bytes,
    holdings: ledger.usage.holdings - 1,
  }
  holding.live = false
  retire_original_holding(ledger, holding)
  Ok(())
}

///|
pub fn reservation_serial(reservation : Reservation) -> Int {
  reservation.serial
}

///|
pub fn holding_serial(holding : Holding) -> Int {
  holding.serial
}

///|
pub fn ledger_limits(ledger : Ledger) -> LedgerLimits {
  ledger.limits
}

///|
/// Limits available to this ledger's own admissions while subledgers are live.
/// Byte allowances already appear as reservations in LedgerUsage; count quotas
/// are excluded here without falsely reporting them as completed/consumed work.
pub fn ledger_admission_limits(ledger : Ledger) -> LedgerLimits {
  {
    ..ledger.limits,
    planning_work: ledger.limits.planning_work - ledger.delegated_planning,
    attempts: ledger.limits.attempts - ledger.delegated_attempts,
    holdings: ledger.limits.holdings - ledger.delegated_holdings,
  }
}

///|
pub fn reservation_open(reservation : Reservation) -> Bool {
  reservation.open
}

///|
pub fn holding_available(ledger : Ledger, holding : Holding) -> Bool {
  physical_equal(ledger, holding.owner) && holding.live
}

///|
pub fn holding_belongs_to(ledger : Ledger, holding : Holding) -> Bool {
  physical_equal(ledger, holding.owner)
}
