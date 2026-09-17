///|
fn run_local_managed_test_task(
  installed : @local_driver.LocalDispatchModule,
  run : @strategy.CapturedDAG,
  task : Int,
  inputs : Array[@execution.ManagedCompletedOutput[Int]],
  rows : Array[Array[String]],
  payload : Int,
  available : Ref[Bool],
) -> (
  @local_driver.LocalManagedDispatchOperations[Int],
  @execution.ManagedCompletedOutput[Int],
) raise {
  let owner = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(run),
    task,
  ).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      inputs,
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  assert_eq(operations.inputs.length(), rows.length())
  for index, transfer in operations.inputs {
    for row in rows[index] {
      (transfer.append)(row).unwrap()
    }
    (transfer.finish)().unwrap()
  }
  (operations.execute)().unwrap()
  (operations.settle)().unwrap()
  let completed = (operations.complete)(payload, operations.storage_bytes, fn() {
    available.val
  }).unwrap()
  assert_true(
    @strategy.captured_managed_task_output_matches(
      run,
      task,
      @pipeline.Step(0),
      completed,
    ),
  )
  (operations, completed)
}

///|
fn local_managed_test_rows(
  operations : @local_driver.LocalManagedDispatchOperations[Int],
) -> Array[String] {
  Array::makei((operations.output_rows)(), index => {
    (operations.output_row)(index).unwrap()
  })
}

///|
test "Local managed group count feeds two real downstream Computes" {
  let (run, issuer) = captured_graph_fixture(local_values_group_chain=true)
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

  let value_live = Ref(true)
  let (value_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    value_live,
  )
  let value_rows = local_managed_test_rows(value_ops)
  assert_eq(value_rows, ["{\"id\":null}", "{\"id\":1}", "{\"id\":1}"])

  let group_live = Ref(true)
  let (group_ops, groups) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [value_rows],
    2,
    group_live,
  )
  let group_rows = local_managed_test_rows(group_ops)
  assert_eq(group_rows, ["{\"id\":null,\"n\":1}", "{\"id\":1,\"n\":2}"])

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [groups],
    [group_rows],
    3,
    first_live,
  )
  assert_eq(local_managed_test_rows(first_ops), group_rows)

  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [groups],
    [group_rows],
    4,
    second_live,
  )
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"n\":1,\"id\":null}", "{\"n\":2,\"id\":1}",
  ])
  assert_true(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(groups))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  group_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (group_ops.close)()
  (group_ops.cleanup_refresh)() |> ignore
  value_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (value_ops.close)()
  (value_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
