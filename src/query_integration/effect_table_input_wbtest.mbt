///|
fn verify_captured_private_table_input(empty : Bool) -> Unit raise {
  let (document, environment, limits) = local_effect_export_fixture(
    table=true,
    empty~,
  )
  let prepared = match
    @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(value) => value
    Err(Candidate(_)) => fail("private Table candidate preparation failed")
    Err(Static(@stage_results.MappingRules(issue))) =>
      fail(
        "private Table Mapping rules failed: " +
        @debug.to_string(@stage_results.effect_mapping_rule_issue_kind(issue)),
      )
    Err(Static(_)) => fail("private Table static closure failed")
    Err(Graph(issue)) =>
      fail("private Table physical graph failed: " + @debug.to_string(issue))
    Err(_) => fail("private Table Host preparation failed")
  }
  let computation = @publication_host.prepared_client_effect_computation_graph(
    prepared,
  )
  assert_true(@strategy.checked_effect_source_at(computation, 0) is None)
  assert_true(
    @strategy.checked_effect_table_input_at(computation, 0) is Some(_),
  )
  assert_true(@strategy.checked_effect_source_at(computation, 1) is Some(_))
  assert_true(@strategy.checked_effect_table_input_at(computation, 1) is None)
  let (admission, run_definition, template, effect_run) = local_effect_open_run(
    prepared,
  )
  let run = @strategy.captured_effect_run_dag(effect_run)
  let (operations, completed, available) = local_effect_execute_managed_values(
    prepared, run,
  )
  // Two ordinary Manifest/Effect Result views have been pinned when the
  // Table pin reaches the same per-task ceiling. Failure rolls both back.
  assert_true(
    @strategy.pin_captured_effect_sources(effect_run, 2)
    is Err(@strategy.Physical(@resources.HoldingLimit)),
  )
  let inputs = @strategy.pin_captured_effect_sources(effect_run, 3).unwrap()
  assert_eq(@strategy.captured_effect_inputs_count(inputs), 2)
  assert_true(@strategy.captured_effect_input_at(inputs, 0) is None)
  assert_true(@strategy.captured_effect_table_input_at(inputs, 1) is None)
  let table = @strategy.captured_effect_table_input_at(inputs, 0).unwrap()
  assert_eq(@strategy.captured_effect_table_input_member(table), 0)
  assert_eq(@strategy.captured_effect_table_input_stage(table), 0)
  assert_eq(@strategy.captured_effect_table_input_task(table), 0)
  let ordinary = @strategy.captured_effect_input_at(inputs, 1).unwrap()
  assert_eq(@strategy.captured_effect_local_result_count(inputs), 2)
  assert_true(@strategy.close_captured_effect_source_port(inputs, 0))
  assert_true(@strategy.captured_effect_input_at(inputs, 1) is Some(_))
  assert_true(@strategy.captured_effect_table_input_at(inputs, 0) is Some(_))
  let borrow = @strategy.captured_effect_table_input_borrow(table)
  assert_true(
    @strategy.captured_table_input_borrow_matches_managed(borrow, completed),
  )
  assert_true(@strategy.captured_table_input_borrow_cell_output(borrow) is None)
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    10,
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
  let occurrence = @strategy.captured_effect_table_input_occurrence(table)
  let preparation = @execution.start_completed_table_input_relation_export(
    output,
    occurrence,
    {
      max_fields: 10,
      max_mapping_work: 100,
      max_order_work: 100,
      max_workspace_entries: 20,
    },
    10,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    row_wire_limits(),
    row_wire_limits(),
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    64,
  ).unwrap()
  assert_true(
    @execution.managed_publication_bridge_matches_table_input_export(
      bridge, completed, preparation, occurrence,
    ),
  )
  let mut ready = false
  for _ in 0..<100 {
    if @execution.advance_completed_table_input_relation_export(preparation, 1).unwrap().0 {
      ready = true
      break
    }
  }
  assert_true(ready)
  let stream = @execution.finish_completed_table_input_relation_export_preparation(
    preparation,
  ).unwrap()
  let text = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), if empty { "[]" } else { "[{\"value\":1}]" })
  assert_eq(@execution.completed_relation_export_field_names(receipt), ["value"])
  assert_eq(
    @execution.relation_schema_wire(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
    "{\"value\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  let definition = @publication_host.issue_captured_client_effect_local_table_definition(
    prepared, inputs, 0, 4096, 32, 8,
  ).unwrap()
  let ordinary_definition = @publication_host.issue_captured_client_effect_local_result_definition(
    prepared, inputs, 1, 4096, 32, 8,
  ).unwrap()
  assert_true(
    @publication_host.client_effect_local_table_definition_cid(definition) !=
    @publication_host.client_effect_local_result_definition_cid(
      ordinary_definition,
    ),
  )
  assert_true(
    @publication_host.issue_captured_client_effect_local_table_definition(
      prepared, inputs, 1, 4096, 32, 8,
    )
    is Err(@publication_host.MissingCapturedInput),
  )
  let program = @program_check.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(prepared),
  )
  let unit_cid = @program_check.unit_definition_cid(program, 0).unwrap()
  let definition_body = "{\"table_input_name\":\"out\",\"unit_definition_cid\":\"" +
    unit_cid +
    "\",\"version\":\"actql-local-table-input-definition/0.1\"}"
  // This independently authored preimage distinguishes the private namespace
  // even though the public Result deliberately has the same name and rows.
  let expected_cid = native_publication_cid(definition_body)
  assert_eq(
    @publication_host.client_effect_local_table_definition_cid(definition),
    expected_cid,
  )
  assert_eq(
    @publication_host.client_effect_local_table_definition_json(definition),
    "{\"self_cid\":\"" +
    expected_cid +
    "\",\"table_input_name\":\"out\",\"unit_definition_cid\":\"" +
    unit_cid +
    "\",\"version\":\"actql-local-table-input-definition/0.1\"}",
  )
  let invocation = @publication_host.issue_source_free_client_effect_local_invocation(
    prepared, 0, 4096, 32, 8,
  ).unwrap()
  let (observation, run_invocation, retention) = private_table_artifact_context(
    template,
  )
  let issue = (receipt : @execution.CompletedRelationExportReceipt) => {
    @publication_host.issue_source_free_client_effect_local_table_artifact(
      prepared, inputs, 0, table, completed, bridge, preparation, definition, invocation,
      receipt, retention, admission, run_definition, run_invocation, observation,
      65536, 4096, 32,
    )
  }
  let artifact = issue(receipt).unwrap()
  assert_eq(
    @publication_host.client_effect_local_artifact_definition_cid(artifact),
    expected_cid,
  )
  assert_eq(
    @publication_host.client_effect_local_artifact_invocation_cid(artifact),
    @publication_host.client_effect_local_invocation_cid(invocation),
  )
  let mapping = @publication_host.client_effect_local_table_storage_mapping(
    artifact, 65536, 4096, 16,
  ).unwrap()
  assert_eq(
    @effect.table_storage_mapping_schema_cid(mapping),
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
  )
  let identity = @publication_host.issue_source_free_client_effect_local_identity(
    prepared, inputs, 0, artifact, 100, 65536, 4096, 32,
  ).unwrap()
  assert_true(
    @publication_host.client_effect_local_identity_matches(
      identity, prepared, 0, artifact,
    ),
  )
  let scope = @request_scope.prepare_logical_request_scope(
    native_publication_cid("effect-authority"),
    "private-table-capture",
    64,
  ).unwrap()
  let operation_wire = (artifact_cid : String) => {
    let prefix = "{\"action\":\"create\",\"catalog_identity_cid\":\"" +
      native_publication_cid("table-catalog") +
      "\",\"data_policy_cid\":\"" +
      native_publication_cid("effect-data-policy") +
      "\",\"effect_identity_cid\":\"" +
      @publication_host.client_effect_local_identity_cid(identity) +
      "\",\"expected_table\":null,\"input_artifact_cid\":\"" +
      artifact_cid +
      "\",\"input_relation_cid\":\"" +
      native_publication_cid(
        "{\"sort\":\"relation\",\"value\":" +
        (if empty { "[]" } else { "[{\"value\":1}]" }) +
        "}",
      ) +
      "\",\"logical_request_scope_cid\":\"" +
      @request_scope.logical_request_scope_cid(scope) +
      "\",\"namespace\":[\"analytics\"],"
    let suffix = "\"schema_cid\":\"" +
      @effect.table_storage_mapping_schema_cid(mapping) +
      "\",\"storage_mapping_cid\":\"" +
      @effect.table_storage_mapping_cid(mapping) +
      "\",\"table_name\":\"private_input\",\"version\":\"actql-table-operation/0.1\"}"
    let request_cid = native_publication_cid(prefix + suffix)
    prefix + "\"request_cid\":\"" + request_cid + "\"," + suffix
  }
  let table_input = @publication_host.bind_client_table_input(
    prepared,
    inputs,
    0,
    artifact,
    identity,
    scope,
    operation_wire(
      @publication_host.client_effect_local_result_artifact_cid(artifact),
    ),
    8192,
    256,
    8,
  ).unwrap()
  assert_true(
    @publication_host.client_table_input_matches_source(
      table_input, artifact, identity,
    ),
  )
  assert_eq(
    @publication_host.client_table_input_schema_wire(table_input),
    "{\"value\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_true(
    @publication_host.bind_client_table_input(
      prepared,
      inputs,
      0,
      artifact,
      identity,
      scope,
      operation_wire(native_publication_cid("equal-but-foreign-artifact")),
      8192,
      256,
      8,
    )
    is Err(@publication_host.ForeignInput),
  )
  // A private Artifact cannot satisfy the ordinary member or full Result
  // Manifest, even when names, schemas and content are equal.
  assert_true(
    @publication_host.issue_source_free_client_effect_local_identity(
      prepared, inputs, 1, artifact, 100, 65536, 4096, 32,
    )
    is Err(@publication_host.ForeignInput),
  )
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared,
      invocation,
      [artifact, artifact],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.ForeignArtifact),
  )
  let (ordinary_preparation, ordinary_receipt) = local_effect_export_receipt(
    output,
    @strategy.captured_effect_input_occurrence(ordinary),
  )
  assert_eq(
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(ordinary_receipt),
    ),
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ),
  )
  assert_true(issue(ordinary_receipt) is Err(@publication_host.ForeignExport))
  @execution.cancel_completed_relation_export_receipt(ordinary_receipt)
  @execution.cancel_completed_result_relation_export(ordinary_preparation)
  |> ignore
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  assert_true(@strategy.captured_effect_table_input_at(inputs, 0) is None)
  // Release revokes the whole capture capability before source lookup.
  assert_true(issue(receipt) is Err(@publication_host.ForeignOwner))
  assert_false(@strategy.captured_table_input_borrow_available(borrow))
  assert_false(
    @strategy.captured_any_result_borrow_available(
      @strategy.captured_effect_input_borrow(ordinary),
    ),
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.close_managed_publication_bridge(bridge)
  available.val = false
  (operations.cleanup_refresh)() |> ignore
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
fn private_table_artifact_context(
  template : @publication.RunEvidenceValue,
) -> (
  @publication.RunEvidenceValue,
  @publication.PublicationContract,
  @publication.PublicationContract,
) {
  let policy = native_publication_cid("effect-data-policy")
  let observation = native_publication_evidence(
    "observation_set",
    "{\"version\":\"actql-observation-set/0.1\",\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"source_evidence_cids\":[],\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"capture_started_at\":null,\"capture_completed_at\":null,\"replayability\":{\"materialized\":false,\"availability_evidence_cids\":[]},\"data_policy_cid\":\"" +
    policy +
    "\"}",
  )
  let invocation = @publication.issue_run_invocation(
    template, observation, 65536, 4096, 32,
  ).unwrap()
  let retention = native_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    native_publication_cid("effect-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-25T01:00:00.000Z\",\"delete_by\":\"2026-09-25T02:00:00.000Z\",\"extension_ceiling_at\":\"2026-09-25T03:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    native_publication_cid("effect-metadata") +
    "\",\"metadata_delete_by\":\"2026-09-25T04:00:00.000Z\",\"clock_contract_cid\":\"" +
    native_publication_cid("effect-clock") +
    "\"}",
  )
  (observation, invocation, retention)
}

///|
test "checked Effect capture distinguishes private Table input from its same-name Result" {
  verify_captured_private_table_input(false)
}

///|
test "checked Effect capture retains an empty typed private Table input" {
  verify_captured_private_table_input(true)
}
