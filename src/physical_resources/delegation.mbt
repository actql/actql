///|
/// One trusted execution domain's bounded subledger. The provisioning attempt
/// and process-local byte envelope belong to the parent; independent Store
/// allocations require their own owner and are not released by this token.
struct ExecutionDelegation {
  owner : Ledger
  reservation : Reservation
  limits : LedgerLimits
  mut planning : Int
  mut attempts : Int
  mut holdings : Int
  mut transferred : Int64
  mut uncertain : Int64
}

///|
pub fn reserve_execution_delegation(
  ledger : Ledger,
  limits : LedgerLimits,
  retained : Int64,
  execution : Int64,
) -> Result[ExecutionDelegation, LedgerIssue] {
  match create_ledger(limits) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if retained < limits.retained_bytes || execution < limits.execution_bytes {
    return Err(InvalidCharge)
  }
  let u = ledger.usage
  if limits.planning_work >
    ledger.limits.planning_work - u.planning_work - ledger.delegated_planning {
    return Err(PlanningLimit)
  }
  // Leave one attempt for provisioning itself; subtraction avoids overflow.
  let attempts = ledger.limits.attempts - u.attempts - ledger.delegated_attempts
  if attempts <= 0 || limits.attempts > attempts - 1 {
    return Err(AttemptLimit)
  }
  if limits.holdings >
    ledger.limits.holdings - u.holdings - ledger.delegated_holdings {
    return Err(HoldingLimit)
  }
  let reservation = match
    reserve_attempt(ledger, limits.transfer_bytes, retained, execution) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  ledger.delegated_planning += limits.planning_work
  ledger.delegated_attempts += limits.attempts
  ledger.delegated_holdings += limits.holdings
  Ok({
    owner: ledger,
    reservation,
    limits,
    planning: 0,
    attempts: 0,
    holdings: 0,
    transferred: 0L,
    uncertain: 0L,
  })
}

///|
pub fn execution_delegation_limits(value : ExecutionDelegation) -> LedgerLimits {
  value.limits
}

///|
/// Installed Host accounting only, not a connector completion claim. Reports
/// are cumulative, bounded and monotonic. Unreported allowances stay reserved.
pub fn report_execution_delegation(
  ledger : Ledger,
  value : ExecutionDelegation,
  usage : LedgerUsage,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(ledger, value.owner) {
    return Err(ForeignOwner)
  }
  match reservation_check(ledger, value.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let limits = value.limits
  if usage.planning_work < value.planning ||
    usage.planning_work > limits.planning_work ||
    usage.attempts < value.attempts ||
    usage.attempts > limits.attempts ||
    usage.holdings < value.holdings ||
    usage.holdings > limits.holdings ||
    usage.transferred_bytes < value.transferred ||
    usage.transferred_bytes > limits.transfer_bytes ||
    usage.uncertain_transfer_bytes < value.uncertain ||
    usage.uncertain_transfer_bytes >
    limits.transfer_bytes - usage.transferred_bytes ||
    usage.reserved_transfer_bytes < 0L ||
    usage.reserved_transfer_bytes >
    limits.transfer_bytes -
    usage.transferred_bytes -
    usage.uncertain_transfer_bytes ||
    usage.held_bytes < 0L ||
    usage.held_bytes > limits.retained_bytes ||
    usage.reserved_retention_bytes < 0L ||
    usage.reserved_retention_bytes > limits.retained_bytes - usage.held_bytes ||
    usage.reserved_execution_bytes < 0L ||
    usage.reserved_execution_bytes > limits.execution_bytes ||
    usage.peak_retention_bytes <
    usage.held_bytes + usage.reserved_retention_bytes ||
    usage.peak_retention_bytes > limits.retained_bytes {
    return Err(InvalidCharge)
  }
  // All validation precedes mutation. The original transfer reservation still
  // contains exactly the unreported allowance, even after earlier checkpoints.
  match
    charge_transfer(
      ledger,
      value.reservation,
      usage.transferred_bytes - value.transferred,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  ledger.delegated_planning -= usage.planning_work - value.planning
  let uncertain = usage.uncertain_transfer_bytes - value.uncertain
  value.reservation.transfer -= uncertain
  ledger.usage = {
    ..ledger.usage,
    uncertain_transfer_bytes: ledger.usage.uncertain_transfer_bytes + uncertain,
    reserved_transfer_bytes: ledger.usage.reserved_transfer_bytes - uncertain,
  }
  ledger.delegated_attempts -= usage.attempts - value.attempts
  ledger.delegated_holdings -= usage.holdings - value.holdings
  ledger.usage = {
    ..ledger.usage,
    planning_work: ledger.usage.planning_work +
    (usage.planning_work - value.planning),
    attempts: ledger.usage.attempts + (usage.attempts - value.attempts),
    holdings: ledger.usage.holdings + (usage.holdings - value.holdings),
  }
  value.planning = usage.planning_work
  value.attempts = usage.attempts
  value.holdings = usage.holdings
  value.transferred = usage.transferred_bytes
  value.uncertain = usage.uncertain_transfer_bytes
  Ok(())
}

///|
/// Call only after confirmed execution-domain stop. An exact final accounting
/// snapshot permits returning unused allowance. Without it, consume the entire
/// remaining quota conservatively; a crash must not reset cumulative budgets.
/// This does not acknowledge independent Store cleanup or result durability.
pub fn settle_execution_delegation(
  ledger : Ledger,
  value : ExecutionDelegation,
  final_usage : LedgerUsage?,
) -> Result[Unit, LedgerIssue] {
  let usage = match final_usage {
    Some(usage) => usage
    None => {
      let limits = value.limits
      {
        planning_work: limits.planning_work,
        attempts: limits.attempts,
        holdings: limits.holdings,
        transferred_bytes: value.transferred,
        uncertain_transfer_bytes: limits.transfer_bytes - value.transferred,
        reserved_transfer_bytes: 0L,
        held_bytes: 0L,
        reserved_retention_bytes: 0L,
        reserved_execution_bytes: 0L,
        peak_retention_bytes: limits.retained_bytes,
      }
    }
  }
  match report_execution_delegation(ledger, value, usage) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  ledger.delegated_planning -= value.limits.planning_work - value.planning
  ledger.delegated_attempts -= value.limits.attempts - value.attempts
  ledger.delegated_holdings -= value.limits.holdings - value.holdings
  settle_reservation(ledger, value.reservation)
}
