///|
/// Real Core tokens on the same original Ledger, with no Source acquisition,
/// native allocation, worker or business Run. These test only the accounting
/// predicate after the caller's separate physical-close gates.
fn source_cleanup_test_ledger() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 4,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 16L,
    retained_bytes: 16L,
    execution_bytes: 16L,
  }).unwrap()
}

///|
test "Source cleanup keeps an original zero-byte capacity reservation pending" {
  let ledger = source_cleanup_test_ledger()
  assert_true(resident_source_compute_capacity_released(ledger))
  let original = @resources.reserve_capacity(ledger, 0L, 0L).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.live_reservations, 1)
  assert_eq(usage.reserved_attempts, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_false(resident_source_compute_capacity_released(ledger))
  @resources.settle_capacity(ledger, original).unwrap()
  assert_true(resident_source_compute_capacity_released(ledger))
}

///|
test "Source cleanup keeps an original zero-byte attempt pending until settlement" {
  let ledger = source_cleanup_test_ledger()
  let original = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
  assert_false(resident_source_compute_capacity_released(ledger))
  @resources.consume_reserved_attempt(ledger, original).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_false(resident_source_compute_capacity_released(ledger))
  @resources.settle_reservation(ledger, original).unwrap()
  assert_true(resident_source_compute_capacity_released(ledger))
}

///|
test "Source cleanup keeps an original zero-byte holding after its attempt settles" {
  let ledger = source_cleanup_test_ledger()
  let original = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let holding = @resources.retain_allocation(ledger, original, 0L).unwrap()
  @resources.settle_reservation(ledger, original).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.holdings, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_false(resident_source_compute_capacity_released(ledger))
  @resources.release_allocation(ledger, holding).unwrap()
  assert_true(resident_source_compute_capacity_released(ledger))
}

///|
test "Source cleanup keeps an original zero-byte delegation pending" {
  let ledger = source_cleanup_test_ledger()
  let original = @resources.reserve_execution_delegation(
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
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.live_delegations, 1)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_false(resident_source_compute_capacity_released(ledger))
  // No child domain was entered. Use the existing conservative missing-report
  // settlement path, never a caller-authored empty final accounting report.
  @resources.settle_execution_delegation(ledger, original, None).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_delegations, 0)
  assert_true(resident_source_compute_capacity_released(ledger))
}

///|
test "Source cleanup allows spent history and peak after all originals settle" {
  let ledger = source_cleanup_test_ledger()
  @resources.charge_planning(ledger, 2).unwrap()
  let original = @resources.reserve_attempt(ledger, 2L, 3L, 4L).unwrap()
  let holding = @resources.retain_allocation(ledger, original, 3L).unwrap()
  @resources.charge_transfer(ledger, original, 2L).unwrap()
  @resources.settle_reservation(ledger, original).unwrap()
  assert_false(resident_source_compute_capacity_released(ledger))
  @resources.release_allocation(ledger, holding).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.planning_work, 2)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.transferred_bytes, 2L)
  assert_eq(usage.peak_retention_bytes, 3L)
  assert_true(resident_source_compute_capacity_released(ledger))
}
