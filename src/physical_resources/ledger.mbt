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
  holdings : Int
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
  mut delegated_planning : Int
  mut delegated_attempts : Int
  mut delegated_holdings : Int
}

///|
struct Reservation {
  owner : Ledger
  serial : Int
  mut transfer : Int64
  mut retention : Int64
  mut execution : Int64
  mut open : Bool
  mut cleanup_pending : Bool
}

///|
/// A holding is one physical allocation, never a content-identity cache entry.
struct Holding {
  owner : Ledger
  serial : Int
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
} derive(Eq, Debug)

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
    delegated_planning: 0,
    delegated_attempts: 0,
    delegated_holdings: 0,
    usage: {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transferred_bytes: 0L,
      uncertain_transfer_bytes: 0L,
      reserved_transfer_bytes: 0L,
      held_bytes: 0L,
      reserved_retention_bytes: 0L,
      reserved_execution_bytes: 0L,
      peak_retention_bytes: 0L,
    },
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
) -> Result[Reservation, LedgerIssue] {
  if transfer_bytes < 0L || retained_bytes < 0L || execution_bytes < 0L {
    return Err(InvalidCharge)
  }
  let u = ledger.usage
  if u.attempts >= ledger.limits.attempts - ledger.delegated_attempts {
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
  let retained = u.held_bytes + u.reserved_retention_bytes + retained_bytes
  ledger.usage = {
    ..u,
    attempts: u.attempts + 1,
    reserved_transfer_bytes: u.reserved_transfer_bytes + transfer_bytes,
    reserved_retention_bytes: u.reserved_retention_bytes + retained_bytes,
    reserved_execution_bytes: u.reserved_execution_bytes + execution_bytes,
    peak_retention_bytes: if retained > u.peak_retention_bytes {
      retained
    } else {
      u.peak_retention_bytes
    },
  }
  Ok({
    owner: ledger,
    serial: u.attempts,
    transfer: transfer_bytes,
    retention: retained_bytes,
    execution: execution_bytes,
    open: true,
    cleanup_pending: false,
  })
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
  Ok(())
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
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > reservation.transfer {
    return Err(TransferLimit)
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
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > reservation.transfer {
    return Err(TransferLimit)
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
  reservation.retention -= bytes
  ledger.usage = {
    ..u,
    holdings: u.holdings + 1,
    reserved_retention_bytes: u.reserved_retention_bytes - bytes,
    held_bytes: u.held_bytes + bytes,
  }
  Ok({ owner: ledger, serial: u.holdings, bytes, live: true, })
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
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let u = ledger.usage
  ledger.usage = {
    ..u,
    reserved_transfer_bytes: u.reserved_transfer_bytes - reservation.transfer,
    reserved_retention_bytes: u.reserved_retention_bytes - reservation.retention,
    reserved_execution_bytes: u.reserved_execution_bytes - reservation.execution,
  }
  reservation.open = false
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
  ledger.usage = {
    ..ledger.usage,
    held_bytes: ledger.usage.held_bytes - holding.bytes,
  }
  holding.live = false
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
