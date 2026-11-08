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

///|
// Logical Owner controls only. The Native physical caller supplies its actual
// retirement receipt; these synthetic values do not assert a physical ACK.
test "unborrowed cleanup reconciliation preserves whole backing and rejects stale credit" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 100L,
  }).unwrap()
  let capacity = reserve_shared_capacity(ledger, 100L).unwrap()
  let allocation = allocate_shared_capacity(capacity, 60L).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  reconcile_unborrowed_shared_allocation_after_cleanup(
    capacity, allocation, 60L, 20L,
  ).unwrap()
  assert_eq(shared_capacity_usage(capacity).capacity, 100L)
  assert_eq(shared_capacity_usage(capacity).allocated, 20L)
  assert_eq(shared_allocation_usage(allocation).bytes, 20L)
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  for (expected, remaining) in [(60L, 0L), (20L, -1L), (20L, 21L)] {
    assert_true(
      reconcile_unborrowed_shared_allocation_after_cleanup(
        capacity, allocation, expected, remaining,
      )
      is Err(InvalidCharge),
    )
    assert_eq(shared_capacity_usage(capacity).allocated, 20L)
    assert_eq(ledger_usage(ledger), before)
  }
  let borrow = borrow_shared_capacity(capacity, allocation).unwrap()
  assert_true(
    reconcile_unborrowed_shared_allocation_after_cleanup(
      capacity, allocation, 20L, 10L,
    )
    is Err(ClosedHolding),
  )
  return_shared_capacity(borrow).unwrap()
  reconcile_unborrowed_shared_allocation_after_cleanup(
    capacity, allocation, 20L, 10L,
  ).unwrap()
  grow_unborrowed_shared_allocation(capacity, allocation, 10L, 50L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 50L)
  assert_eq(ledger_usage(ledger), before)
  retire_shared_capacity(allocation).unwrap()
  assert_true(
    reconcile_unborrowed_shared_allocation_after_cleanup(
      capacity, allocation, 50L, 0L,
    )
    is Err(ClosedHolding),
  )
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
}
