///|
test "captured consumer retirement keeps original Source backing until its actual release" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 0L, 100L, 0L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  let released = Ref(false)
  @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=() => {
    released.val
  }).unwrap()
  let read = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  assert_true(@execution.producer_read_available(read))
  assert_false(@strategy.retire_captured_task_outputs(run))
  assert_true(@strategy.retire_captured_task_consumers(run))
  assert_false(@execution.producer_read_available(read))
  assert_true(@strategy.captured_task_retirement_pending(run))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
  assert_true(@resources.holding_available(ledger, holding))
  released.val = true
  @strategy.refresh_captured_retention(run)
  assert_false(@strategy.captured_task_retirement_pending(run))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(@strategy.retire_captured_task_consumers(run))
}

///|
test "captured consumer retirement cannot acknowledge an independent completed output pin" {
  let (run, _) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let pin = @strategy.pin_captured_task_output(run, 1, Step(1), 1).unwrap()
  let original = @strategy.captured_output_pin_materialized(pin)
  assert_false(@strategy.retire_captured_task_consumers(run))
  assert_true(@strategy.captured_task_retirement_pending(run))
  assert_true(@execution.completed_output_available(original))
  assert_true(@strategy.release_captured_output_pin(pin))
  assert_true(@strategy.retire_captured_task_consumers(run))
  assert_false(@execution.completed_output_available(original))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}
