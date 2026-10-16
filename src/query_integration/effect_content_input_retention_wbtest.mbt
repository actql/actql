///|
test "Content input final fence keeps the exact original consumer pin without invoking availability" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture()
  let input = @strategy.captured_effect_input_at(inputs, 0).unwrap()
  let separate = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
  let separate_input = @strategy.captured_effect_input_at(separate, 0).unwrap()
  assert_true(@strategy.captured_effect_input_retained(inputs, 0, input))
  assert_false(@strategy.captured_effect_input_retained(separate, 0, input))
  assert_false(
    @strategy.captured_effect_input_retained(inputs, 0, separate_input),
  )
  assert_false(@strategy.captured_effect_input_retained(inputs, 1, input))
  assert_false(@strategy.captured_effect_input_retained(inputs, -1, input))
  available.val = false
  // Retention is not physical availability, current authorization or a grant.
  assert_true(@strategy.captured_effect_input_retained(inputs, 0, input))
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.captured_effect_input_retained(inputs, 0, input))
  assert_true(
    @strategy.captured_effect_input_retained(separate, 0, separate_input),
  )
  assert_true(@strategy.release_captured_effect_inputs(separate))
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  let run = @strategy.captured_effect_run_dag(captured)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}
