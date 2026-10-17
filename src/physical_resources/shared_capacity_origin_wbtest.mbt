///|
test "shared capacity original Ledger match is readonly and closes with its original reservation" {
  let limits : LedgerLimits = {
    planning_work: 10,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }
  let ledger = create_ledger(limits).unwrap()
  let foreign = create_ledger(limits).unwrap()
  let capacity = reserve_shared_capacity(ledger, 40L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(shared_capacity_matches_ledger(capacity, ledger))
  assert_false(shared_capacity_matches_ledger(capacity, foreign))
  let after = ledger_usage(ledger)
  assert_eq(after.planning_work, before.planning_work)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.holdings, before.holdings)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.uncertain_transfer_bytes, before.uncertain_transfer_bytes)
  assert_eq(after.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(after.peak_retention_bytes, before.peak_retention_bytes)
  let allocation = allocate_shared_capacity(capacity, 20L).unwrap()
  let borrow = borrow_shared_capacity(capacity, allocation).unwrap()
  assert_true(shared_capacity_matches_ledger(capacity, ledger))
  close_shared_capacity(capacity).unwrap()
  assert_false(shared_capacity_matches_ledger(capacity, ledger))
  assert_eq(settle_shared_capacity(capacity), Err(InvalidCharge))
  return_shared_capacity(borrow).unwrap()
  retire_shared_capacity(allocation).unwrap()
  release_shared_capacity(allocation).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_false(shared_capacity_matches_ledger(capacity, ledger))
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}
