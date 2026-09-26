///|
fn assert_local_managed_set_variant(
  operation : String,
  duplicates : String,
  expected : Array[String],
  expected_reordered : Array[String],
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_set_operation=operation,
    local_values_set_duplicates=duplicates,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 128000000L,
      execution_bytes: 134217728L,
    }),
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

  // Each input and the set run as separate selected tasks.
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 6)
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(2))
  let left_live = Ref(true)
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
  )
  let right_live = Ref(true)
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
  )
  let producer_live = Ref(true)
  let set_advances = Ref(0)
  let (producer_ops, produced) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [local_managed_test_rows(left_ops), local_managed_test_rows(right_ops)],
    3,
    producer_live,
    execution_quantum=1,
    execution_advances=Some(set_advances),
    require_provider=true,
  )
  assert_true(set_advances.val > 4)
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(rows, expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [produced],
    [rows],
    4,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [produced],
    [rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(local_managed_test_rows(second_ops), expected_reordered)

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(produced))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  for pair in [(1, left_live, left_ops), (2, right_live, right_ops)] {
    let (task, live, ops) = pair
    live.val = false
    @strategy.close_captured_task_output(run, task)
    (ops.close)()
    (ops.cleanup_refresh)() |> ignore
  }
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
test "Local managed row sets preserve variants and two consumers" {
  assert_local_managed_set_variant(
    "except",
    "all",
    [
      "{\"id\":1,\"label\":\"a\"}", "{\"id\":2,\"label\":\"b\"}", "{\"id\":null,\"label\":\"n\"}",
    ],
    [
      "{\"label\":\"a\",\"id\":1}", "{\"label\":\"b\",\"id\":2}", "{\"label\":\"n\",\"id\":null}",
    ],
  )
  assert_local_managed_set_variant(
    "intersect",
    "all",
    ["{\"id\":1,\"label\":\"a\"}"],
    ["{\"label\":\"a\",\"id\":1}"],
  )
  assert_local_managed_set_variant(
    "except",
    "distinct",
    ["{\"id\":2,\"label\":\"b\"}", "{\"id\":null,\"label\":\"n\"}"],
    ["{\"label\":\"b\",\"id\":2}", "{\"label\":\"n\",\"id\":null}"],
  )
  assert_local_managed_set_variant(
    "intersect",
    "distinct",
    ["{\"id\":1,\"label\":\"a\"}"],
    ["{\"label\":\"a\",\"id\":1}"],
  )
}
