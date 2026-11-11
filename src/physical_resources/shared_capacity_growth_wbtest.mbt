///|
fn growth_test_ledger() -> Ledger {
  create_ledger({
    planning_work: 10,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 100L,
    retained_bytes: 0L,
    execution_bytes: 400L,
  }).unwrap()
}

///|
test "same original growth reserves before acquisition and preserves old and new borrowers" {
  let ledger = growth_test_ledger()
  let capacity = reserve_shared_capacity(ledger, 100L).unwrap()
  let control = allocate_shared_capacity(capacity, 10L).unwrap()
  let old = allocate_shared_capacity(capacity, 90L).unwrap()
  let old_borrow = borrow_shared_capacity(capacity, old).unwrap()
  let reservation = capacity.reservation
  let serial = ledger.next_attempt_serial
  let growth = begin_shared_capacity_growth(capacity, control, 300L, 10L).unwrap()
  assert_true(physical_equal(capacity.reservation, reservation))
  assert_eq(ledger.next_attempt_serial, serial)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 300L)
  assert_eq(shared_allocation_usage(old).readers, 1)
  assert_true(allocate_shared_capacity(capacity, 1L) is Err(ClosedReservation))
  assert_true(borrow_shared_capacity(capacity, old) is Err(ClosedHolding))
  assert_true(
    begin_shared_capacity_growth(capacity, control, 400L, 10L)
    is Err(ClosedHolding),
  )
  complete_shared_capacity_growth_after_acquisition(growth).unwrap()
  let newer = allocate_shared_capacity(capacity, 150L).unwrap()
  let newer_borrow = borrow_shared_capacity(capacity, newer).unwrap()
  retire_shared_capacity(old).unwrap()
  retire_shared_capacity(newer).unwrap()
  assert_eq(release_shared_capacity(old), Err(InvalidCharge))
  assert_eq(release_shared_capacity(newer), Err(InvalidCharge))
  close_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 300L)
  return_shared_capacity(old_borrow).unwrap()
  release_shared_capacity(old).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 300L)
  return_shared_capacity(newer_borrow).unwrap()
  release_shared_capacity(newer).unwrap()
  retire_shared_capacity(control).unwrap()
  release_shared_capacity(control).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_attempt_serial, serial)
}

///|
test "refused growth and atomic failed acquisition preserve original ledger and serials" {
  let ledger = growth_test_ledger()
  let capacity = reserve_shared_capacity(ledger, 100L).unwrap()
  let control = allocate_shared_capacity(capacity, 10L).unwrap()
  let borrower = borrow_shared_capacity(capacity, control).unwrap()
  let usage = ledger_usage(ledger)
  let serial = ledger.next_attempt_serial
  let capacity_serial = ledger.next_capacity_serial
  assert_true(
    begin_shared_capacity_growth(capacity, control, 401L, 10L)
    is Err(ExecutionLimit),
  )
  assert_eq(ledger_usage(ledger), usage)
  let growth = begin_shared_capacity_growth(capacity, control, 300L, 10L).unwrap()
  abort_shared_capacity_growth_after_cleanup(growth).unwrap()
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_attempt_serial, serial)
  assert_eq(ledger.next_capacity_serial, capacity_serial)
  assert_eq(shared_capacity_usage(capacity).capacity, 100L)
  assert_eq(shared_capacity_usage(capacity).allocated, 10L)
  assert_eq(shared_allocation_usage(control).bytes, 10L)
  assert_eq(shared_allocation_usage(control).readers, 1)
  assert_eq(
    abort_shared_capacity_growth_after_cleanup(growth),
    Err(ForeignOwner),
  )
  return_shared_capacity(borrower).unwrap()
  retire_shared_capacity(control).unwrap()
  release_shared_capacity(control).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
}

///|
test "unknown growth outcome stays charged and cancellation is not cleanup" {
  let ledger = growth_test_ledger()
  let capacity = reserve_shared_capacity(ledger, 100L).unwrap()
  let control = allocate_shared_capacity(capacity, 10L).unwrap()
  let growth = begin_shared_capacity_growth(capacity, control, 300L, 10L).unwrap()
  close_shared_capacity(capacity).unwrap()
  retire_shared_capacity(control).unwrap()
  assert_eq(release_shared_capacity(control), Err(InvalidCharge))
  assert_eq(settle_shared_capacity(capacity), Err(InvalidCharge))
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 300L)
  // The original supplier has now confirmed the actual addition's cleanup.
  abort_shared_capacity_growth_after_cleanup(growth).unwrap()
  release_shared_capacity(control).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "whole physical addition stays in the same parent claim until actual cleanup" {
  let ledger = growth_test_ledger()
  let capacity = reserve_shared_capacity(ledger, 100L).unwrap()
  let control = allocate_shared_capacity(capacity, 10L).unwrap()
  let old = allocate_shared_capacity(capacity, 90L).unwrap()
  let reader = borrow_shared_capacity(capacity, old).unwrap()
  let token = capacity.reservation
  let serial = ledger.next_attempt_serial
  let growth = begin_shared_capacity_growth(capacity, control, 300L, 200L).unwrap()
  assert_true(physical_equal(capacity.reservation, token))
  assert_eq(shared_capacity_usage(capacity).allocated, 300L)
  assert_eq(shared_allocation_usage(control).bytes, 210L)
  assert_eq(shared_allocation_usage(old).bytes, 90L)
  assert_eq(shared_allocation_usage(old).readers, 1)
  assert_eq(ledger.next_attempt_serial, serial)
  assert_true(allocate_shared_capacity(capacity, 1L) is Err(_))
  assert_true(release_shared_capacity(control) is Err(_))
  // Only this original transaction's acknowledged no-acquisition can undo it.
  abort_shared_capacity_growth_after_cleanup(growth).unwrap()
  assert_eq(shared_capacity_usage(capacity).capacity, 100L)
  assert_eq(shared_capacity_usage(capacity).allocated, 100L)
  let second = begin_shared_capacity_growth(capacity, control, 300L, 200L).unwrap()
  complete_shared_capacity_growth_after_acquisition(second).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 300L)
  assert_true(allocate_shared_capacity(capacity, 1L) is Err(RetentionLimit))
  close_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 300L)
  retire_shared_capacity(old).unwrap()
  return_shared_capacity(reader).unwrap()
  release_shared_capacity(old).unwrap()
  retire_shared_capacity(control).unwrap()
  release_shared_capacity(control).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_attempt_serial, serial)
}
