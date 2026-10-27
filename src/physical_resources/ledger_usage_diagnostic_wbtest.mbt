///|
test "owned usage diagnostic preserves all count fields and exact Int64 numeric lexemes" {
  // Independent diagnostic DATA vector, not a report/charge/admission receipt.
  let usage : LedgerUsage = {
    planning_work: 3,
    attempts: 1,
    reserved_attempts: 2,
    holdings: 4,
    live_reservations: 5,
    live_delegations: 6,
    transferred_bytes: 9007199254740993L,
    uncertain_transfer_bytes: 37L,
    reserved_transfer_bytes: 17L,
    held_bytes: 19L,
    reserved_retention_bytes: 23L,
    reserved_execution_bytes: 29L,
    peak_retention_bytes: 9223372036854775807L,
  }
  assert_eq(
    ledger_usage_diagnostic_json(usage),
    "{\"planning_work\":3,\"attempts\":1,\"reserved_attempts\":2,\"holdings\":4,\"live_reservations\":5,\"live_delegations\":6,\"transferred_bytes\":9007199254740993,\"uncertain_transfer_bytes\":37,\"reserved_transfer_bytes\":17,\"held_bytes\":19,\"reserved_retention_bytes\":23,\"reserved_execution_bytes\":29,\"peak_retention_bytes\":9223372036854775807}",
  )
}

///|
test "generated usage array preserves complete declaration order and exact Int64 values" {
  let usage : LedgerUsage = {
    planning_work: 101,
    attempts: 102,
    reserved_attempts: 103,
    holdings: 104,
    live_reservations: 105,
    live_delegations: 106,
    transferred_bytes: 9007199254740993L,
    uncertain_transfer_bytes: 108L,
    reserved_transfer_bytes: 109L,
    held_bytes: 110L,
    reserved_retention_bytes: 111L,
    reserved_execution_bytes: 112L,
    peak_retention_bytes: 9223372036854775807L,
  }
  assert_eq(ledger_usage_values(usage), [
    101L, 102L, 103L, 104L, 105L, 106L, 9007199254740993L, 108L, 109L, 110L, 111L,
    112L, 9223372036854775807L,
  ])
}

///|
test "pending resource observation sees real zero-byte tokens but preserves cumulative spent facts" {
  let ledger = create_ledger(backed_test_limits()).unwrap()
  assert_false(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  let unused = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  assert_true(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  settle_reservation(ledger, unused).unwrap()
  assert_false(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  let capacity = reserve_capacity(ledger, 0L, 0L).unwrap()
  assert_true(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  settle_capacity(ledger, capacity).unwrap()
  assert_false(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  charge_planning(ledger, 2).unwrap()
  let spent = reserve_attempt(ledger, 2L, 3L, 4L).unwrap()
  let holding = retain_allocation(ledger, spent, 3L).unwrap()
  charge_transfer(ledger, spent, 2L).unwrap()
  settle_reservation(ledger, spent).unwrap()
  assert_true(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  release_allocation(ledger, holding).unwrap()
  let usage = ledger_usage(ledger)
  assert_eq(usage.planning_work, 2)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.transferred_bytes, 2L)
  assert_eq(usage.peak_retention_bytes, 3L)
  assert_false(ledger_usage_has_pending_resources(usage))
  // Observing no pending counter does not reset the already consumed serials.
  assert_eq(ledger.next_attempt_serial, Some(2))
  assert_eq(ledger.next_capacity_serial, Some(-2))
}

///|
test "pending observation preserves uncertainty and actual delegated live occupancy" {
  let ledger = create_ledger(backed_test_limits()).unwrap()
  let delegated = reserve_execution_delegation(
    ledger,
    {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    },
    0L,
    0L,
  ).unwrap()
  assert_true(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  settle_execution_delegation(ledger, delegated, Some(initial_ledger_usage)).unwrap()
  assert_false(ledger_usage_has_pending_resources(ledger_usage(ledger)))
  let uncertain = reserve_attempt(ledger, 3L, 0L, 0L).unwrap()
  mark_transfer_uncertain(ledger, uncertain, 3L).unwrap()
  settle_reservation(ledger, uncertain).unwrap()
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 3L)
  assert_true(ledger_usage_has_pending_resources(ledger_usage(ledger)))
}
