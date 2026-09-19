///|
test "Local managed nest reaches two consumers and final reclamation" {
  let ledger_limits : @resources.LedgerLimits = {
    planning_work: 10000,
    attempts: 20,
    holdings: 20,
    transfer_bytes: 300000L,
    retained_bytes: 134217728L,
    execution_bytes: 536870912L,
  }
  let (run, issuer) = captured_graph_fixture(
    local_values_nest_chain=true,
    ledger_limits=Some(ledger_limits),
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
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 10000,
        max_columns: 10,
      },
      row: {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 10,
        max_text_bytes: 1000,
      },
      max_batch_bytes: 1024,
    },
    None,
  ).unwrap()
  assert_eq(
    @strategy.captured_task_aggregate_output_limit(
      run,
      3,
      0,
      "items",
      @connector.array_items_output_unit(),
    ),
    Some(3L),
  )
  assert_eq(
    @strategy.captured_task_aggregate_output_limit(
      run,
      3,
      0,
      "items",
      @connector.nest_grouped_bytes_output_unit(),
    ),
    Some(10000L),
  )
  assert_eq(
    @strategy.captured_task_aggregate_output_limit(
      run,
      3,
      0,
      "items",
      @connector.nest_attached_bytes_output_unit(),
    ),
    Some(10000L),
  )

  let parent_live = Ref(true)
  let (parent_ops, parents) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    parent_live,
  )
  let parent_rows = local_managed_test_rows(parent_ops)
  let child_live = Ref(true)
  let (child_ops, children) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    child_live,
  )
  let child_rows = local_managed_test_rows(child_ops)

  let nest_live = Ref(true)
  let (nest_ops, nested) = run_local_managed_test_task(
    installed,
    run,
    3,
    [parents, children],
    [parent_rows, child_rows],
    3,
    nest_live,
  )
  let nested_rows = local_managed_test_rows(nest_ops)
  let expected = [
    "{\"id\":1,\"items\":[{\"amount\":null},{\"amount\":10}],\"key\":1}", "{\"id\":2,\"items\":[{\"amount\":null},{\"amount\":10}],\"key\":1}",
    "{\"id\":3,\"items\":[],\"key\":null}", "{\"id\":4,\"items\":[],\"key\":2}",
  ]
  assert_eq(nested_rows, expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [nested],
    [nested_rows],
    4,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [nested],
    [nested_rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), [
    "{\"id\":1,\"key\":1,\"items\":[{\"amount\":null},{\"amount\":10}]}", "{\"id\":2,\"key\":1,\"items\":[{\"amount\":null},{\"amount\":10}]}",
    "{\"id\":3,\"key\":null,\"items\":[]}", "{\"id\":4,\"key\":2,\"items\":[]}",
  ])
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"items\":[{\"amount\":null},{\"amount\":10}],\"id\":1,\"key\":1}", "{\"items\":[{\"amount\":null},{\"amount\":10}],\"id\":2,\"key\":1}",
    "{\"items\":[],\"id\":3,\"key\":null}", "{\"items\":[],\"id\":4,\"key\":2}",
  ])

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(nested))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  nest_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (nest_ops.close)()
  (nest_ops.cleanup_refresh)() |> ignore
  child_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (child_ops.close)()
  (child_ops.cleanup_refresh)() |> ignore
  parent_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (parent_ops.close)()
  (parent_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
