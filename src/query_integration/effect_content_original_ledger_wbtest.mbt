///|
test "Content workspace correspondence reads the same live original captured Ledger without charging" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture()
  let run = @strategy.captured_effect_run_dag(captured)
  let ledger = @strategy.captured_dag_ledger(run)
  // Explicit test-only component capacity, not a normal Content profile.
  let capacity = @resources.reserve_shared_capacity(ledger, 17L).unwrap()
  let same_limits = @resources.create_ledger(@resources.ledger_limits(ledger)).unwrap()
  let foreign = @resources.reserve_shared_capacity(same_limits, 17L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.captured_effect_inputs_shared_capacity_current(inputs, capacity),
  )
  assert_false(
    @strategy.captured_effect_inputs_shared_capacity_current(inputs, foreign),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let separate = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
  assert_true(
    @strategy.captured_effect_inputs_shared_capacity_current(separate, capacity),
  )
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(
    @strategy.captured_effect_inputs_shared_capacity_current(inputs, capacity),
  )
  assert_true(
    @strategy.captured_effect_inputs_shared_capacity_current(separate, capacity),
  )
  @resources.close_shared_capacity(capacity).unwrap()
  assert_false(
    @strategy.captured_effect_inputs_shared_capacity_current(separate, capacity),
  )
  @resources.settle_shared_capacity(capacity).unwrap()
  @resources.close_shared_capacity(foreign).unwrap()
  @resources.settle_shared_capacity(foreign).unwrap()
  assert_true(@strategy.release_captured_effect_inputs(separate))
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "Content workspace correspondence refuses a stopped original Run while its pin remains" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture()
  let run = @strategy.captured_effect_run_dag(captured)
  let ledger = @strategy.captured_dag_ledger(run)
  let capacity = @resources.reserve_shared_capacity(ledger, 17L).unwrap()
  assert_true(
    @strategy.captured_effect_inputs_shared_capacity_current(inputs, capacity),
  )
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  assert_false(
    @strategy.captured_effect_inputs_shared_capacity_current(inputs, capacity),
  )
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}
