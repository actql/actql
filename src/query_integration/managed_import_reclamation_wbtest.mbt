///|
fn managed_import_reclamation_program() -> @program_check.CheckedProgram raise {
  let rows = Array::makei(100, index => {
    "{\"id\":" + index.to_string() + ",\"label\":\"retained\"}"
  }).join(",")
  let text =
    #|{"version":"actql/0.1","id":"buffered-input","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"values_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[
  let suffix =
    #|]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"values_a","result":"r"}}},"steps":[{"select":["id","label"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"values_a","result":"r"}}},"steps":[{"select":["label","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["label","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  query_checked_program_fixture(program_text=Some(text + rows + suffix))
}

///|
test "managed unfinished input keeps reservation across buffer reclamation polls" {
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(managed_import_reclamation_program()),
    preparation_work=10000,
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
        max_nodes: 10000,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let producer_live = Ref(true)
  let (producer_operations, producer) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
    require_provider=true,
  )
  let rows = Array::makei(100, index => {
    "{\"id\":" + index.to_string() + ",\"label\":\"retained\"}"
  })
  assert_eq(local_managed_test_rows(producer_operations), rows)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    2,
    [producer],
    [[]],
    require_provider=true,
    finish_inputs=false,
  )
  let transfer = operations.inputs[0]
  // Import 99 rows through the real receiving port, without sealing it.
  for row in 0..<99 {
    (transfer.append)(rows[row]).unwrap()
  }
  let admitted = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    admitted.reserved_execution_bytes > before.reserved_execution_bytes,
  )
  assert_true((operations.request_cancel)())
  assert_true((operations.execution_stopped)())
  (operations.settle)().unwrap()
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
    admitted.reserved_execution_bytes,
  )
  assert_false((operations.cleanup_refresh)())
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
    admitted.reserved_execution_bytes,
  )
  let work = (operations.cumulative_provider_work)().unwrap()
  assert_eq(work, 0L)
  let mut cleaned = false
  for _ in 0..<10 {
    if (operations.cleanup_refresh)() {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  let released = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(released.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(released.transferred_bytes, admitted.transferred_bytes)
  assert_eq((operations.cumulative_provider_work)().unwrap(), work)
  assert_false(@strategy.captured_task_completed(run, 2))
  assert_true(
    (transfer.append)(rows[0]) is Err(Configuration(InputUnavailable)),
  )
  assert_true((transfer.finish)() is Err(Configuration(InputUnavailable)))
  assert_true((operations.cleanup_refresh)())
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
    released,
  )
  assert_true(@execution.managed_completed_output_available(producer))
  assert_eq(local_managed_test_rows(producer_operations), rows)
  // Successful finalization already retired the admission buffer before the
  // settled hook released execution scratch. The immutable completed output
  // remains separately held and readable until its original owner is revoked.
  assert_eq(released.reserved_execution_bytes, 0L)
  assert_true(released.held_bytes > 0L)
  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (producer_operations.close)()
  assert_false(@execution.managed_completed_output_available(producer))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
    0L,
  )
  assert_true((producer_operations.cleanup_refresh)())
  assert_eq((operations.cumulative_provider_work)().unwrap(), work)
  assert_true((producer_operations.cleanup_refresh)())
  for task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let reclaimed = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(reclaimed.reserved_execution_bytes, 0L)
  assert_eq(reclaimed.reserved_retention_bytes, 0L)
  assert_eq(reclaimed.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
