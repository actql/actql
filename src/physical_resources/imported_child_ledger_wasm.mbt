///|
// These are fixed installation imports, never Client packet fields or a
// caller-supplied callback. E binds the same actual channel/VM/FD/domain.
fn imported_child_admit(nonce : Int64) -> Int = "actql_host" "execution_child_admit"

///|
fn imported_child_current(nonce : Int64) -> Int = "actql_host" "execution_child_current"

///|
fn imported_child_limit(nonce : Int64, ordinal : Int) -> Int64 = "actql_host" "execution_child_limit"

///|
fn imported_child_capacity(nonce : Int64, ordinal : Int) -> Int64 = "actql_host" "execution_child_capacity"

///|
fn imported_child_stop(nonce : Int64) -> Int = "actql_host" "execution_child_stop"

///|
fn imported_child_report(
  nonce : Int64,
  planning : Int,
  attempts : Int,
  holdings : Int,
  transferred : Int64,
  uncertain : Int64,
  reserved_transfer : Int64,
  held : Int64,
  reserved_retention : Int64,
  reserved_execution : Int64,
  peak_retention : Int64,
  reserved_attempts : Int,
  live_reservations : Int,
  live_delegations : Int,
) -> Int = "actql_host" "execution_child_report"

///|
fn imported_child_port(
  nonce : Int64,
) -> Result[
  (
    (Int64) -> Int,
    (Int64) -> Int,
    (Int64, Int) -> Int64,
    (Int64, Int) -> Int64,
    (Int64, LedgerUsage) -> Int,
    (Int64) -> Int,
  ),
  ImportedChildLedgerIssue,
] {
  if nonce <= 0L {
    return Err(InvalidOriginal)
  }
  Ok(
    (
      imported_child_admit,
      imported_child_current,
      imported_child_limit,
      imported_child_capacity,
      (nonce, usage) => {
        imported_child_report(
          nonce,
          usage.planning_work,
          usage.attempts,
          usage.holdings,
          usage.transferred_bytes,
          usage.uncertain_transfer_bytes,
          usage.reserved_transfer_bytes,
          usage.held_bytes,
          usage.reserved_retention_bytes,
          usage.reserved_execution_bytes,
          usage.peak_retention_bytes,
          usage.reserved_attempts,
          usage.live_reservations,
          usage.live_delegations,
        )
      },
      imported_child_stop,
    ),
  )
}
