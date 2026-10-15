///|
fn borrowed_workspace_ledger() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 0,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 100L,
  }).unwrap()
}

///|
test "borrowed workspace returns only its reader after both physical observations" {
  let ledger = borrowed_workspace_ledger()
  let capacity = @resources.reserve_shared_capacity(ledger, 100L).unwrap()
  let allocation = @resources.allocate_shared_capacity(capacity, 60L).unwrap()
  let sibling = @resources.allocate_shared_capacity(capacity, 40L).unwrap()
  let sibling_borrow = @resources.borrow_shared_capacity(capacity, sibling).unwrap()
  let stopped = Ref(false)
  let cleaned = Ref(false)
  let stop_calls = Ref(0)
  let cleanup_calls = Ref(0)
  let before = @resources.ledger_usage(ledger)
  let loan = borrow_workspace(
    capacity,
    allocation,
    () => {
      stop_calls.val += 1
      stopped.val
    },
    () => {
      cleanup_calls.val += 1
      cleaned.val
    },
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 1)
  assert_eq(close_workspace(loan), Err(CleanupPending))
  assert_eq(cleanup_calls.val, 0)
  stopped.val = true
  assert_eq(close_workspace(loan), Err(CleanupPending))
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 1)
  assert_eq(@resources.shared_allocation_usage(sibling).readers, 1)
  cleaned.val = true
  close_workspace(loan).unwrap()
  close_workspace(loan).unwrap()
  assert_eq(stop_calls.val, 2)
  assert_eq(cleanup_calls.val, 2)
  assert_true(loan.backing is ReturnedBorrow)
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 0)
  assert_false(@resources.shared_allocation_usage(allocation).retiring)
  assert_false(@resources.shared_allocation_usage(allocation).released)
  assert_eq(@resources.shared_allocation_usage(sibling).readers, 1)
  assert_false(@resources.shared_capacity_usage(capacity).closing)
  assert_eq(@resources.shared_capacity_usage(capacity).allocated, 100L)
  assert_eq(@resources.ledger_usage(ledger), before)
  // A later reader is still legal; the loan did not retire its allocation.
  let next = @resources.borrow_shared_capacity(capacity, allocation).unwrap()
  @resources.return_shared_capacity(next).unwrap()
  @resources.return_shared_capacity(sibling_borrow).unwrap()
  @resources.retire_shared_capacity(allocation).unwrap()
  @resources.release_shared_capacity(allocation).unwrap()
  @resources.retire_shared_capacity(sibling).unwrap()
  @resources.release_shared_capacity(sibling).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "borrowed workspace refuses foreign retiring and released allocations before callbacks" {
  let ledger = borrowed_workspace_ledger()
  let capacity = @resources.reserve_shared_capacity(ledger, 60L).unwrap()
  let other = @resources.reserve_shared_capacity(ledger, 40L).unwrap()
  let allocation = @resources.allocate_shared_capacity(capacity, 60L).unwrap()
  let calls = Ref(0)
  let observe = () => {
    calls.val += 1
    true
  }
  assert_true(
    borrow_workspace(other, allocation, observe, observe) is Err(Resource(_)),
  )
  @resources.retire_shared_capacity(allocation).unwrap()
  assert_true(
    borrow_workspace(capacity, allocation, observe, observe) is Err(Resource(_)),
  )
  @resources.release_shared_capacity(allocation).unwrap()
  assert_true(
    borrow_workspace(capacity, allocation, observe, observe) is Err(Resource(_)),
  )
  assert_eq(calls.val, 0)
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 0)
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  @resources.close_shared_capacity(other).unwrap()
  @resources.settle_shared_capacity(other).unwrap()
}

///|
test "borrowed workspace retains unknown cleanup through arena retirement" {
  let ledger = borrowed_workspace_ledger()
  let capacity = @resources.reserve_shared_capacity(ledger, 100L).unwrap()
  let allocation = @resources.allocate_shared_capacity(capacity, 100L).unwrap()
  let cleaned = Ref(false)
  let loan = borrow_workspace(capacity, allocation, () => true, () => {
    cleaned.val
  }).unwrap()
  @resources.retire_shared_capacity(allocation).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  assert_eq(close_workspace(loan), Err(CleanupPending))
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 1)
  assert_true(@resources.release_shared_capacity(allocation) is Err(_))
  assert_true(@resources.settle_shared_capacity(capacity) is Err(_))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  cleaned.val = true
  close_workspace(loan).unwrap()
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 0)
  assert_false(@resources.shared_allocation_usage(allocation).released)
  @resources.release_shared_capacity(allocation).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "borrowed workspace does not manufacture a read control placement allowance" {
  let (_, origin, claim, owned) = original_workspace_pair_fixture(
    Ref(true),
    Ref(true),
  )
  let allocation = @resources.allocate_shared_capacity(owned.capacity, 25L).unwrap()
  let loan = borrow_workspace(owned.capacity, allocation, () => true, () => true).unwrap()
  assert_true(
    issue_workspace_original_read(claim, origin, loan)
    is Err(@resources.IncompleteInventory),
  )
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 1)
  close_workspace(loan).unwrap()
  @resources.retire_shared_capacity(allocation).unwrap()
  @resources.release_shared_capacity(allocation).unwrap()
  @resources.stop_funded_read(claim).unwrap()
  @resources.settle_funded_read(claim, true).unwrap()
  close_workspace(owned).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
}
