///|
/// Compose domain demands in their original Ledger dimensions. This is DATA,
/// not a policy selection, Ledger constructor, grant, debit or new owner.
/// Retention and execution are independent limits; adding them must not invent
/// an execution >= retention restriction or credit a negative contribution.
pub fn add_ledger_limits(
  first : LedgerLimits,
  second : LedgerLimits,
) -> LedgerLimits? {
  if first.planning_work < 0 ||
    first.attempts < 0 ||
    first.holdings < 0 ||
    first.transfer_bytes < 0L ||
    first.retained_bytes < 0L ||
    first.execution_bytes < 0L ||
    second.planning_work < 0 ||
    second.attempts < 0 ||
    second.holdings < 0 ||
    second.transfer_bytes < 0L ||
    second.retained_bytes < 0L ||
    second.execution_bytes < 0L {
    return None
  }
  if first.planning_work > 2147483647 - second.planning_work ||
    first.attempts > 2147483647 - second.attempts ||
    first.holdings > 2147483647 - second.holdings ||
    first.transfer_bytes > 9223372036854775807L - second.transfer_bytes ||
    first.retained_bytes > 9223372036854775807L - second.retained_bytes ||
    first.execution_bytes > 9223372036854775807L - second.execution_bytes {
    return None
  }
  Some({
    planning_work: first.planning_work + second.planning_work,
    attempts: first.attempts + second.attempts,
    holdings: first.holdings + second.holdings,
    transfer_bytes: first.transfer_bytes + second.transfer_bytes,
    retained_bytes: first.retained_bytes + second.retained_bytes,
    execution_bytes: first.execution_bytes + second.execution_bytes,
  })
}
