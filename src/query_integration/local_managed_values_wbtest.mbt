///|
test "Local managed execution admits checked zero-input values without a dummy producer" {
  let (run, issuer) = captured_graph_fixture(values=true)
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

  // The control predecessor is independent of the zero-input data shape.
  captured_graph_local(run, 1).unwrap()
  assert_eq(@strategy.next_captured_task(run), Some(2))
  let graph = @strategy.captured_dag_graph(run)
  let owner = @strategy.graph_task_owner(graph, 2).unwrap()
  let prepared = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(prepared).unwrap()
  assert_eq(operations.inputs.length(), 0)
  (operations.execute)().unwrap()
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"id\":7}")
  (operations.settle)().unwrap()
  let available = Ref(true)
  let completed = (operations.complete)(7, operations.storage_bytes, fn() {
    available.val
  }).unwrap()
  assert_true(
    @strategy.captured_managed_task_output_matches(
      run,
      2,
      @pipeline.Step(0),
      completed,
    ),
  )
  assert_eq(@execution.managed_completed_output_row_count(completed), 1)
  assert_true(@execution.managed_completed_output_available(completed))

  @strategy.close_captured_task_output(run, 2)
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
