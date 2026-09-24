///|
fn run_binary_receiver_input_limit(cross : Bool) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_external_chain=cross,
    local_values_append_chain=!cross,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 268435456L,
    }),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let base = limits.local_execution
  let rows = base.rows
  let producer_installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    base,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: rows.max_rows,
      metadata_entries: rows.metadata_entries,
      retained_entries: rows.retained_entries,
      operation_entries: rows.operation_entries,
      input_values: {
        max_nodes: 0,
        max_text_bytes: rows.input_values.max_text_bytes,
        max_depth: rows.input_values.max_depth,
        max_work: rows.input_values.max_work,
      },
      output_values: rows.output_values,
    },
    max_work: base.max_work,
    max_frames: base.max_frames,
  }
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
    },
    None,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    producer_installed,
    {
      max_rows: 100,
      values: rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
    },
    None,
  ).unwrap()
  let left_live = Ref(true)
  let (left_ops, left) = run_local_managed_test_task(
    producer_installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
  )
  let right_live = Ref(true)
  let (right_ops, right) = run_local_managed_test_task(
    producer_installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
  )
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    3,
    [left, right],
    [local_managed_test_rows(left_ops), local_managed_test_rows(right_ops)],
    require_provider=true,
  )
  let mut rejected = false
  let mut polls = 0
  while !rejected && polls < 100 {
    polls += 1
    match (operations.advance)(1) {
      Err(
        @local_driver.Configuration(@connector.Execution(@execution.InputLimit))
      ) => rejected = true
      Ok(observation) => {
        assert_false(observation.complete)
        assert_true(observation.work <= 1L)
      }
      _ => fail("binary receiver did not report its input value limit")
    }
  }
  assert_true(rejected)
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(3, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  (operations.close)()
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 3))
  assert_true(@execution.managed_completed_output_available(left))
  assert_true(@execution.managed_completed_output_available(right))
  left_live.val = false
  right_live.val = false
  @strategy.close_captured_task_output(run, 1)
  @strategy.close_captured_task_output(run, 2)
  (left_ops.close)()
  (right_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
  (right_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.close_captured_task_output(run, 3)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host rejects cross join receiving input value limit" {
  run_binary_receiver_input_limit(true)
}

///|
test "standard Host rejects append receiving input value limit" {
  run_binary_receiver_input_limit(false)
}
