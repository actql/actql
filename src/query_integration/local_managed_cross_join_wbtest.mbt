///|
fn run_local_managed_cross_join(singleton : Bool) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_chain=true,
    local_values_cross_singleton=singleton,
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let producer_live = Ref(true)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
  )
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(
    rows,
    if singleton {
      ["{\"id\":1,\"tag\":\"a\"}", "{\"id\":2,\"tag\":\"a\"}"]
    } else {
      [
        "{\"id\":1,\"tag\":\"a\"}", "{\"id\":1,\"tag\":\"b\"}", "{\"id\":2,\"tag\":\"a\"}",
        "{\"id\":2,\"tag\":\"b\"}",
      ]
    },
  )
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    2,
    [producer],
    [rows],
    2,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    3,
    [producer],
    [rows],
    3,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(
    local_managed_test_rows(second_ops),
    if singleton {
      ["{\"tag\":\"a\",\"id\":1}", "{\"tag\":\"a\",\"id\":2}"]
    } else {
      [
        "{\"tag\":\"a\",\"id\":1}", "{\"tag\":\"b\",\"id\":1}", "{\"tag\":\"a\",\"id\":2}",
        "{\"tag\":\"b\",\"id\":2}",
      ]
    },
  )
  first_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))
  second_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed cross join reaches two consumers in left-major order" {
  run_local_managed_cross_join(false)
}

///|
test "Local managed singleton cross join validates before two consumers" {
  run_local_managed_cross_join(true)
}

///|
test "captured cross join retains the authored output restriction" {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_chain=true,
    local_values_cross_output_guard=Some(2),
  )
  assert_eq(@strategy.captured_task_join_output_limit(run, 1, 4), Some(2L))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}
