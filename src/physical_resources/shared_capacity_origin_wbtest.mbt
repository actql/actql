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
  assert_eq(ledger_usage(ledger), before)
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
