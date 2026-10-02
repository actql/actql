///|
// Diagnostic only: reuse the registered Local driver and existing DAG fixture.
// The serial operation list and input values come from the typed corpus.
test "generated serial capacity custody diagnostic" {
  let pending = @env.get_env_var("ACTQL_RELATION_PIPELINE_CUSTODY_MODE").unwrap() == "pending"
  let checked = query_checked_program_fixture(
    local_values_unary_chain=Some("capacity-custody-probe"),
    parameter_json="{}",
  )
  let graph = @strategy.prepare_checked_dag(
    checked, physical_graph_owners(checked), 10, 10000, source_free_root=true,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.graph_task_selected_step(graph, 0), None)
  assert_eq(@strategy.graph_task_prefix_end(graph, 0), None)
  let ledger = @resources.create_ledger({
    planning_work: 10000, attempts: 10, holdings: 10, transfer_bytes: 300000L,
    retained_bytes: 32000000L, execution_bytes: 134217728L,
  }).unwrap()
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [task_test_generated(owner)],
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
  let setup = @local_driver.prepare_local_managed_dispatch(
    installed, [], @execution.process_managed_obligations(owner), 0L,
  ).unwrap().unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  assert_eq(@execution.generated_sequence_step_count(task_test_generated(owner)), 3)
  let (_, execution_capacity) = @local_driver.local_managed_dispatch_site_capacity(setup).unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  assert_eq(operations.inputs.length(), 0)
  let mut polls = 0
  while @local_connector.custody_child_start_count() < 2 {
    assert_false((operations.advance)(1).unwrap().complete)
    polls += 1
    assert_true(polls < 100)
  }
  assert_eq(@local_connector.custody_child_start_count(), 2)
  assert_false((operations.advance)(1).unwrap().complete)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_false(@strategy.captured_task_completed(run, 0))
  let work_before = (operations.cumulative_provider_work)().unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes
  println("ACTQL_CUSTODY_STAGE:before-settlement")
  (operations.settle)().unwrap()
  let after = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes
  let work_after = (operations.cumulative_provider_work)().unwrap()
  assert_eq(work_after, work_before)
  if pending {
    assert_eq(after, before)
  }
  println("ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup")
  println("ACTQL_CUSTODY:{\"executionCapacity\":" + execution_capacity.to_string() +
    ",\"before\":" + before.to_string() + ",\"after\":" + after.to_string() +
    ",\"workBefore\":" + work_before.to_string() + ",\"workAfter\":" + work_after.to_string() + "}")
  // No capacity-safety assertion is weakened to match this diagnostic.
  if pending {
    assert_false((operations.cleanup_refresh)())
    assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes, before)
    assert_false((operations.cleanup_refresh)())
    assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes, before)
    assert_eq((operations.cumulative_provider_work)().unwrap(), work_before)
    assert_eq(@local_connector.custody_child_start_count(), 2)
  }
  assert_true((operations.cleanup_refresh)())
  let final_usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes
  assert_eq(final_usage, before - execution_capacity)
  assert_eq((operations.cumulative_provider_work)().unwrap(), work_before)
  assert_eq(@local_connector.custody_child_start_count(), 2)
  assert_true((operations.cleanup_refresh)())
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes, final_usage)
  assert_true((operations.advance)(1) is Err(_))
  assert_eq(@local_connector.custody_child_start_count(), 2)
  assert_eq((operations.cumulative_provider_work)().unwrap(), work_before)
  println("ACTQL_CUSTODY_STAGE:after-provider-cleanup")
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
}
