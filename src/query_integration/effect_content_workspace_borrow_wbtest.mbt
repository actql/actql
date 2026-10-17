///|
// Actual captured Run and Resource owners. Capacities are explicit test-only
// allocations, not a normal Content supplier, read grant or physical ACK.
test "Content workspace borrows the original allocation without another reservation or sibling retirement" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture()
  let run = @strategy.captured_effect_run_dag(captured)
  let ledger = @strategy.captured_dag_ledger(run)
  let capacity = @resources.reserve_shared_capacity(ledger, 17L).unwrap()
  let first = @resources.allocate_shared_capacity(capacity, 7L).unwrap()
  let sibling = @resources.allocate_shared_capacity(capacity, 10L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let borrow = @strategy.borrow_captured_effect_input_workspace(
    inputs, capacity, first,
  ).unwrap()
  let other = @strategy.borrow_captured_effect_input_workspace(
    inputs, capacity, sibling,
  ).unwrap()
  let same = @strategy.borrow_captured_effect_input_workspace(
    inputs, capacity, first,
  ).unwrap()
  assert_eq(@resources.shared_allocation_usage(first).readers, 2)
  assert_eq(@resources.shared_allocation_usage(sibling).readers, 1)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.holdings, before.holdings)
  assert_eq(after.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(@resources.shared_capacity_usage(capacity).allocated, 17L)
  @resources.retire_shared_capacity(first).unwrap()
  assert_true(@resources.release_shared_capacity(first) is Err(InvalidCharge))
  @resources.return_shared_capacity(borrow).unwrap()
  assert_true(@resources.return_shared_capacity(borrow) is Err(InvalidCharge))
  assert_eq(@resources.shared_allocation_usage(first).readers, 1)
  assert_eq(@resources.shared_allocation_usage(sibling).readers, 1)
  @resources.return_shared_capacity(same).unwrap()
  @resources.release_shared_capacity(first).unwrap()
  assert_eq(@resources.shared_capacity_usage(capacity).allocated, 10L)
  assert_false(@resources.shared_allocation_usage(sibling).retiring)
  assert_false(@resources.shared_allocation_usage(sibling).released)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  // Revoking the input view neither returns nor acknowledges the physical loan.
  assert_eq(@resources.shared_allocation_usage(sibling).readers, 1)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  assert_true(
    @strategy.borrow_captured_effect_input_workspace(inputs, capacity, sibling)
    is Err(ForeignOwner),
  )
  @resources.return_shared_capacity(other).unwrap()
  @resources.retire_shared_capacity(sibling).unwrap()
  @resources.release_shared_capacity(sibling).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let settled = @resources.ledger_usage(ledger)
  assert_eq(settled.held_bytes, 0L)
  assert_eq(settled.reserved_execution_bytes, 0L)
  assert_eq(settled.reserved_retention_bytes, 0L)
}

///|
test "Content workspace rejects foreign Run and same-Ledger allocation substitution before acquiring a reader" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture()
  let run = @strategy.captured_effect_run_dag(captured)
  let ledger = @strategy.captured_dag_ledger(run)
  let capacity = @resources.reserve_shared_capacity(ledger, 17L).unwrap()
  let allocation = @resources.allocate_shared_capacity(capacity, 17L).unwrap()
  let separate_capacity = @resources.reserve_shared_capacity(ledger, 17L).unwrap()
  let separate_allocation = @resources.allocate_shared_capacity(
    separate_capacity, 17L,
  ).unwrap()
  assert_true(
    @strategy.borrow_captured_effect_input_workspace(
      inputs, capacity, separate_allocation,
    )
    is Err(ForeignOwner),
  )
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 0)
  assert_eq(@resources.shared_allocation_usage(separate_allocation).readers, 0)
  let (_, foreign_capture, foreign_inputs, foreign_operations, foreign_available
  ) = published_store_capture_fixture()
  assert_true(
    @strategy.borrow_captured_effect_input_workspace(
      foreign_inputs, capacity, allocation,
    )
    is Err(ForeignOwner),
  )
  assert_eq(@resources.shared_allocation_usage(allocation).readers, 0)
  // Same Ledger alone does not select a physical phase. The trusted supplier
  // must select its original capacity/allocation; this primitive proves only
  // the exact allocation owner and live captured Run, not that assignment.
  let selected = @strategy.borrow_captured_effect_input_workspace(
    inputs, separate_capacity, separate_allocation,
  ).unwrap()
  @resources.return_shared_capacity(selected).unwrap()
  @resources.retire_shared_capacity(allocation).unwrap()
  assert_true(
    @strategy.borrow_captured_effect_input_workspace(
      inputs, capacity, allocation,
    )
    is Err(ClosedHolding),
  )
  @resources.release_shared_capacity(allocation).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  assert_true(
    @strategy.borrow_captured_effect_input_workspace(
      inputs, capacity, allocation,
    )
    is Err(ForeignOwner),
  )
  @resources.settle_shared_capacity(capacity).unwrap()
  @resources.retire_shared_capacity(separate_allocation).unwrap()
  @resources.release_shared_capacity(separate_allocation).unwrap()
  @resources.close_shared_capacity(separate_capacity).unwrap()
  @resources.settle_shared_capacity(separate_capacity).unwrap()
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(@strategy.release_captured_effect_inputs(foreign_inputs))
  available.val = false
  foreign_available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  (foreign_operations.close)()
  (foreign_operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let foreign_run = @strategy.captured_effect_run_dag(foreign_capture)
  @strategy.stop_captured_dag(foreign_run)
  @strategy.refresh_captured_retention(foreign_run)
  let settled = @resources.ledger_usage(ledger)
  assert_eq(settled.held_bytes, 0L)
  assert_eq(settled.reserved_execution_bytes, 0L)
  assert_eq(settled.reserved_retention_bytes, 0L)
}
