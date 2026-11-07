///|
test "unborrowed control growth preserves original reservation and refuses stale or live borrower" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 100L,
  }).unwrap()
  let capacity = reserve_shared_capacity(ledger, 100L).unwrap()
  let control = allocate_shared_capacity(capacity, 20L).unwrap()
  let usage = ledger_usage(ledger)
  let serial = ledger.next_attempt_serial
  grow_unborrowed_shared_allocation(capacity, control, 20L, 50L).unwrap()
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_attempt_serial, serial)
  assert_eq(shared_allocation_usage(control).bytes, 50L)
  assert_eq(shared_capacity_usage(capacity).allocated, 50L)
  assert_eq(
    grow_unborrowed_shared_allocation(capacity, control, 20L, 60L),
    Err(InvalidCharge),
  )
  assert_eq(
    grow_unborrowed_shared_allocation(capacity, control, 50L, 101L),
    Err(RetentionLimit),
  )
  let borrow = borrow_shared_capacity(capacity, control).unwrap()
  assert_eq(
    grow_unborrowed_shared_allocation(capacity, control, 50L, 60L),
    Err(ClosedHolding),
  )
  return_shared_capacity(borrow).unwrap()
  grow_unborrowed_shared_allocation(capacity, control, 50L, 60L).unwrap()
  retire_shared_capacity(control).unwrap()
  assert_eq(
    grow_unborrowed_shared_allocation(capacity, control, 60L, 70L),
    Err(ClosedHolding),
  )
  release_shared_capacity(control).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
}
