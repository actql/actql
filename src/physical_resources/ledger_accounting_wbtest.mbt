///|
test "complete accounting DATA snapshot preserves declared order and exact Int64 values" {
  let ledger = create_ledger({
    planning_work: 31,
    attempts: 32,
    holdings: 33,
    transfer_bytes: 9007199254740993L,
    retained_bytes: 35L,
    execution_bytes: 36L,
  }).unwrap()
  // Independent observation DATA vector, not a valid report, lifecycle
  // transition or a claim that these counters came from physical work.
  ledger.usage = {
    planning_work: 41,
    attempts: 42,
    reserved_attempts: 43,
    holdings: 44,
    live_reservations: 45,
    live_delegations: 46,
    transferred_bytes: 9007199254740995L,
    uncertain_transfer_bytes: 48L,
    reserved_transfer_bytes: 49L,
    held_bytes: 50L,
    reserved_retention_bytes: 51L,
    reserved_execution_bytes: 52L,
    peak_retention_bytes: 9223372036854775807L,
  }
  let original = ledger_usage(ledger)
  let first = ledger_limits_usage_values(ledger)
  assert_eq(first, [
    31L, 32L, 33L, 9007199254740993L, 35L, 36L, 41L, 42L, 43L, 44L, 45L, 46L, 9007199254740995L,
    48L, 49L, 50L, 51L, 52L, 9223372036854775807L,
  ])
  first[3] = 0L
  first[18] = 0L
  let next = ledger_limits_usage_values(ledger)
  assert_eq(next[3], 9007199254740993L)
  assert_eq(next[18], 9223372036854775807L)
  assert_eq(ledger_usage(ledger), original)
}
