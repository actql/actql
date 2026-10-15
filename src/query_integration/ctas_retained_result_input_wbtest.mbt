///|
test "ordinary Store captures its filtered Result separately from an earlier public Result" {
  let (_, environment, limits) = local_effect_export_fixture(table=true)
  // Independent machine control: the public row precedes the false filter;
  // the ordinary Result-backed Store receives the empty, fully Required row.
  let document =
    #|{"version":"actql/0.1","id":"ctas-retained-input","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"original"},{"from":"original","filter":"value = 2","as":"filtered"}],"results":{"before_write":{"from":"original","fields":["value"]},"written":{"from":"filtered","fields":["value"]}},"effects":{"save":{"store":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"written"}}}}}],"results":{"before_write":{"from":{"stage":"main","result":"before_write"}}}}
  let prepared = @publication_host.prepare_client_effect_computation(
    document, Json, environment, None, [], limits,
  ).unwrap()
  for name in ["before_write", "written"] {
    let definition = @publication_host.issue_client_effect_local_result_definition(
      prepared, 0, name, 4096, 64, 8,
    ).unwrap()
    assert_true(
      @publication_host.client_effect_local_result_definition_matches(
        definition, prepared, 0, name,
      ),
    )
  }
  let invocation = @publication_host.issue_source_free_client_effect_local_invocation(
    prepared, 0, 4096, 64, 8,
  ).unwrap()
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared, invocation, [], 4096, 64, 8,
    ) is Err(@publication_host.IncompleteResults),
  )
  let (_, _, _, captured) = local_effect_open_run(prepared)
  let run = @strategy.captured_effect_run_dag(captured)
  let sequences = @client_local_host.prepare_client_effect_local_sequences(
    prepared,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    None,
  ).unwrap()
  assert_eq(sequences.length(), 1)
  let (operations, completed, available) = local_effect_execute_managed_values(
    prepared, run, generated=Some(sequences[0]),
  )
  let pins = @strategy.pin_captured_effect_sources(captured, 3).unwrap()
  assert_eq(@strategy.captured_effect_inputs_count(pins), 1)
  assert_eq(@strategy.captured_effect_local_result_count(pins), 2)
  let definition = @publication_host.issue_captured_client_effect_local_result_definition(
    prepared, pins, 0, 4096, 64, 8,
  ).unwrap()
  assert_true(
    @publication_host.client_effect_local_result_definition_matches(
      definition, prepared, 0, "written",
    ),
  )
  let input = @strategy.captured_effect_input_at(pins, 0).unwrap()
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row,
      { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let (preparation, receipt) = local_effect_export_receipt(
    output,
    @strategy.captured_effect_input_occurrence(input),
  )
  assert_eq(@execution.completed_relation_export_measurement(receipt).row_count, 0)
  @execution.cancel_completed_relation_export_receipt(receipt)
  preparation |> ignore
  assert_true(@strategy.release_captured_effect_inputs(pins))
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}
