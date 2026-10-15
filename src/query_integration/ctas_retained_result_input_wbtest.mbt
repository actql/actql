///|
test "ordinary Store Manifest requires a declared Result that no Effect consumes" {
  let (_, environment, limits) = local_effect_export_fixture(table=true)
  // Reduced independent control: both Results use one Values task. Unlike the
  // installed two-task CTAS control, this isolates only the Manifest inventory.
  // The installed false filter, NULL column and expected rows remain unchanged.
  let document =
    #|{"version":"actql/0.1","id":"ctas-retained-input","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"original"}],"results":{"before_write":{"from":"original","fields":["value"]},"written":{"from":"original","fields":["value"]}},"effects":{"save":{"store":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"written"}}}}}],"results":{"before_write":{"from":{"stage":"main","result":"before_write"}}}}
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let (admission, run_definition, template, captured) = local_effect_open_run(
    prepared,
  )
  let run = @strategy.captured_effect_run_dag(captured)
  let (operations, completed, available) = local_effect_execute_managed_values(
    prepared, run,
  )
  let pins = @strategy.pin_captured_effect_sources(captured, 3).unwrap()
  assert_eq(@strategy.captured_effect_inputs_count(pins), 1)
  assert_eq(@strategy.captured_effect_local_result_count(pins), 2)
  let input = @strategy.captured_effect_input_at(pins, 0).unwrap()
  assert_eq(
    @execution.managed_result_occurrence_name(
      @strategy.captured_effect_input_occurrence(input),
    ),
    "written",
  )
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let invocation = @publication_host.issue_source_free_client_effect_local_invocation(
    prepared, 0, 4096, 64, 8,
  ).unwrap()
  let (observation, run_invocation, retention) = private_table_artifact_context(
    template,
  )
  let artifacts : Array[@publication_host.ClientEffectLocalResultArtifact] = []
  let receipts : Array[@execution.CompletedRelationExportReceipt] = []
  for name in ["before_write", "written"] {
    let mut result_index = -1
    for index in 0..<@strategy.captured_effect_local_result_count(pins) {
      let result = @strategy.captured_effect_local_result_at(pins, index).unwrap()
      let occurrence = @strategy.captured_any_result_borrow_occurrence(
        @strategy.captured_effect_local_result_borrow(result),
      )
      if @execution.managed_result_occurrence_name(occurrence) == name {
        result_index = index
      }
    }
    assert_true(result_index >= 0)
    let result = @strategy.captured_effect_local_result_at(pins, result_index).unwrap()
    let occurrence = @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    )
    let (preparation, receipt) = local_effect_export_receipt(output, occurrence)
    assert_eq(
      @execution.completed_relation_export_measurement(receipt).row_count,
      1,
    )
    let exported = @strategy.bind_captured_effect_local_result_managed_export(
      pins, result_index, completed, bridge, preparation,
    ).unwrap()
    let definition = @publication_host.issue_client_effect_local_result_definition(
      prepared, 0, name, 4096, 64, 8,
    ).unwrap()
    artifacts.push(
      @publication_host.issue_source_free_exported_client_effect_local_result_artifact(
        prepared, pins, exported, definition, invocation, receipt, retention, admission,
        run_definition, run_invocation, observation, 65536, 4096, 32,
      ).unwrap(),
    )
    receipts.push(receipt)
  }
  // Passing only the consumed member cannot represent the complete Manifest.
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared,
      invocation,
      [artifacts[1]],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.IncompleteResults),
  )
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared, invocation, artifacts, 65536, 4096, 32,
    )
    is Ok(_),
  )
  for receipt in receipts {
    @execution.cancel_completed_relation_export_receipt(receipt)
  }
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
