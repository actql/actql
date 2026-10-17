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

///|
test "original byte workspace borrower stops matching on return retirement and close without dropping its debt" {
  for ending in 0..<3 {
    let limits : LedgerLimits = {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 5L,
      execution_bytes: 13L,
    }
    let ledger = create_ledger(limits).unwrap()
    let foreign = create_ledger(limits).unwrap()
    let capacity = reserve_shared_workspace_capacity(ledger, 5L, 13L).unwrap()
    let allocation = allocate_shared_capacity(capacity, 13L).unwrap()
    let borrower = borrow_shared_capacity(capacity, allocation).unwrap()
    assert_true(shared_borrow_matches_ledger(borrower, ledger))
    assert_false(shared_borrow_matches_ledger(borrower, foreign))
    assert_eq(ledger_usage(ledger).attempts, 0)
    if ending == 0 {
      return_shared_capacity(borrower).unwrap()
    } else if ending == 1 {
      retire_shared_capacity(allocation).unwrap()
    } else {
      close_shared_capacity(capacity).unwrap()
    }
    assert_false(shared_borrow_matches_ledger(borrower, ledger))
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 5L)
    assert_eq(ledger_usage(ledger).reserved_execution_bytes, 13L)
    if ending != 0 {
      assert_eq(release_shared_capacity(allocation), Err(InvalidCharge))
      return_shared_capacity(borrower).unwrap()
    }
    if ending != 1 {
      retire_shared_capacity(allocation).unwrap()
    }
    release_shared_capacity(allocation).unwrap()
    if ending != 2 {
      close_shared_capacity(capacity).unwrap()
    }
    settle_shared_capacity(capacity).unwrap()
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}
