///|
// Diagnostic only: reuse the registered Local driver and existing DAG fixture.
// The serial operation list and input values come from the typed corpus.
test "generated serial capacity custody diagnostic" {
  let (run, issuer) = captured_graph_fixture(
    local_values_unary_chain=Some("capacity-custody-probe"),
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
  let source_live = Ref(true)
  let (source_ops, source_output) = run_local_managed_test_task(
    installed, run, 1, [], [], 1, source_live, require_provider=true,
  )
  let graph = @strategy.captured_dag_graph(run)
  let owner = @strategy.graph_task_owner(graph, 2).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
    installed, [source_output], @execution.process_managed_obligations(owner), 0L,
  ).unwrap().unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  assert_eq(@execution.generated_sequence_step_count(dispatch_test_generated(run)[1]), 2)
  let (_, execution_capacity) = @local_driver.local_managed_dispatch_site_capacity(setup).unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  assert_eq(operations.inputs.length(), 1)
  for row in local_managed_test_rows(source_ops) {
    (operations.inputs[0].append)(row).unwrap()
  }
  (operations.inputs[0].finish)().unwrap()
  assert_false((operations.advance)(1).unwrap().complete)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes
  println("ACTQL_CUSTODY_STAGE:before-settlement")
  (operations.settle)().unwrap()
  let after = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes
  println("ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup")
  println("ACTQL_CUSTODY:{\"executionCapacity\":" + execution_capacity.to_string() +
    ",\"before\":" + before.to_string() + ",\"after\":" + after.to_string() + "}")
  // No capacity-safety assertion is weakened to match this diagnostic.
  assert_true((operations.cleanup_refresh)())
  println("ACTQL_CUSTODY_STAGE:after-provider-cleanup")
  source_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (source_ops.close)()
  (source_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  @mock.close_mock_query_issuer(issuer)
}
