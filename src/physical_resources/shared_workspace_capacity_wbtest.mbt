///|
test "byte workspace keeps the original attempt budget and exact allocation debt" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 7L,
    retained_bytes: 0L,
    execution_bytes: 13L,
  }).unwrap()
  let attempt = reserve_attempt(ledger, 7L, 0L, 0L).unwrap()
  charge_transfer(ledger, attempt, 3L).unwrap()
  settle_reservation(ledger, attempt).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 1)
  let capacity = reserve_shared_workspace_capacity(ledger, 13L).unwrap()
  assert_true(shared_capacity_matches_ledger(capacity, ledger))
  let allocation = allocate_shared_capacity(capacity, 9L).unwrap()
  let sibling = allocate_shared_capacity(capacity, 4L).unwrap()
  let first = borrow_shared_capacity(capacity, allocation).unwrap()
  let second = borrow_shared_capacity(capacity, allocation).unwrap()
  retire_shared_capacity(allocation).unwrap()
  close_shared_capacity(capacity).unwrap()
  assert_eq(release_shared_capacity(allocation), Err(InvalidCharge))
  assert_eq(settle_shared_capacity(capacity), Err(InvalidCharge))
  return_shared_capacity(first).unwrap()
  assert_eq(return_shared_capacity(first), Err(InvalidCharge))
  assert_eq(release_shared_capacity(allocation), Err(InvalidCharge))
  return_shared_capacity(second).unwrap()
  release_shared_capacity(allocation).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 13L)
  retire_shared_capacity(sibling).unwrap()
  release_shared_capacity(sibling).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).transferred_bytes, 3L)
}

///|
test "byte workspace refuses invalid and short capacity without consuming attempt or holdings" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 13L,
  }).unwrap()
  assert_true(
    reserve_shared_workspace_capacity(ledger, 0L) is Err(InvalidCharge),
  )
  assert_true(
    reserve_shared_workspace_capacity(ledger, -1L) is Err(InvalidCharge),
  )
  assert_true(
    reserve_shared_workspace_capacity(ledger, 14L) is Err(ExecutionLimit),
  )
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  let capacity = reserve_shared_workspace_capacity(ledger, 13L).unwrap()
  let foreign = create_ledger(ledger_admission_limits(ledger)).unwrap()
  let foreign_capacity = reserve_shared_workspace_capacity(foreign, 13L).unwrap()
  let allocation = allocate_shared_capacity(capacity, 13L).unwrap()
  assert_true(!shared_capacity_matches_ledger(capacity, foreign))
  assert_true(
    borrow_shared_capacity(foreign_capacity, allocation) is Err(ForeignOwner),
  )
  assert_true(
    allocate_shared_capacity(capacity, 1L) is Err(RetentionLimit),
  )
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger_usage(ledger).holdings, 0)
  assert_eq(ledger_usage(ledger).transferred_bytes, 0L)
  retire_shared_capacity(allocation).unwrap()
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
  close_shared_capacity(foreign_capacity).unwrap()
  settle_shared_capacity(foreign_capacity).unwrap()
}
