///|
fn verify_captured_private_table_input(
  empty : Bool,
  repeated? : Bool = false,
) -> Unit raise {
  let (document, environment, limits) = local_effect_export_fixture(
    table=true,
    empty~,
  )
  let document = if repeated {
    let ordinary = "\"copy\":{\"store\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"other\"}}}"
    let ordinary = if document.contains(ordinary) {
      ordinary
    } else {
      ordinary.replace(old="\"store\":", new="\"create\":")
    }
    document.replace(
      old=ordinary,
      new=ordinary +
        ",\"again\":{\"store\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"table_input\":\"out\"}}}",
    )
  } else {
    document
  }
  if repeated {
    assert_true(document.contains("\"again\":"))
  }
  let limits = if repeated {
    {
      ..limits,
      max_members: 3,
      effects: { ..limits.effects, max_members: 3, },
    }
  } else {
    limits
  }
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
  let pins = if repeated { 4 } else { 3 }
  assert_true(
    @strategy.pin_captured_effect_sources(effect_run, pins - 1)
    is Err(@strategy.Physical(@resources.HoldingLimit)),
  )
  let inputs = @strategy.pin_captured_effect_sources(effect_run, pins).unwrap()
  assert_eq(
    @strategy.captured_effect_inputs_count(inputs),
    if repeated {
      3
    } else {
      2
    },
  )
  assert_true(@strategy.captured_effect_input_at(inputs, 0) is None)
  assert_true(@strategy.captured_effect_table_input_at(inputs, 1) is None)
  let table = @strategy.captured_effect_table_input_at(inputs, 0).unwrap()
  assert_eq(@strategy.captured_effect_table_input_member(table), 0)
  assert_eq(@strategy.captured_effect_table_input_stage(table), 0)
  assert_eq(@strategy.captured_effect_table_input_task(table), 0)
  let ordinary = @strategy.captured_effect_input_at(inputs, 1).unwrap()
  assert_true(@strategy.captured_effect_inputs_share_view(inputs, 0, 0))
  assert_false(@strategy.captured_effect_inputs_share_view(inputs, 0, 1))
  assert_false(@strategy.captured_effect_inputs_share_view(inputs, 1, 0))
  assert_false(@strategy.captured_effect_inputs_share_view(inputs, 0, 3))
  assert_eq(@strategy.captured_effect_local_result_count(inputs), 2)
  let borrow = @strategy.captured_effect_table_input_borrow(table)
  let second_borrow = @strategy.borrow_captured_table_input_output(
    run,
    @strategy.captured_effect_table_input_task(table),
    @strategy.captured_effect_table_input_occurrence(table),
    pins + 1,
  ).unwrap()
  assert_true(
    @strategy.captured_table_input_borrows_share_view(borrow, second_borrow),
  )
  assert_true(@strategy.release_captured_table_input_borrow(second_borrow))
  assert_false(@strategy.release_captured_table_input_borrow(second_borrow))
  assert_false(
    @strategy.captured_table_input_borrows_share_view(borrow, second_borrow),
  )
  assert_true(@strategy.captured_table_input_borrow_available(borrow))
  assert_true(@strategy.close_captured_effect_source_port(inputs, 0))
  assert_true(@strategy.captured_effect_input_at(inputs, 1) is Some(_))
  assert_true(@strategy.captured_effect_table_input_at(inputs, 0) is Some(_))
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
  let invocation = @publication_host.issue_source_free_captured_client_effect_local_invocation(
    prepared, inputs, 0, 4096, 32, 8,
  ).unwrap()
  let ordinary_invocation = @publication_host.issue_source_free_captured_client_effect_local_invocation(
    prepared, inputs, 1, 4096, 32, 8,
  ).unwrap()
  assert_eq(
    @publication_host.client_effect_local_invocation_cid(invocation),
    @publication_host.client_effect_local_invocation_cid(ordinary_invocation),
  )
  assert_true(
    @publication_host.issue_source_free_captured_client_effect_local_invocation(
      prepared, inputs, 3, 4096, 32, 8,
    )
    is Err(@publication_host.MissingCapturedInput),
  )
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
  let mapping = @local_table.issue_table_storage_mapping(
    @publication_host.client_effect_local_relation_export_receipt(artifact),
    65536,
    4096,
    16,
  ).unwrap()
  let reference = @local_table.storage_mapping_reference(
    mapping, 65536, 4096, 16,
  ).unwrap()
  assert_eq(
    @local_table.table_storage_mapping_schema_cid(mapping),
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
      "\",\"input_carrier\":{\"cid\":\"" +
      native_publication_cid(
        "{\"sort\":\"relation\",\"value\":" +
        (if empty { "[]" } else { "[{\"value\":1}]" }) +
        "}",
      ) +
      "\",\"kind\":\"relation\"},\"logical_request_scope_cid\":\"" +
      @request_scope.logical_request_scope_cid(scope) +
      "\",\"namespace\":[\"analytics\"],"
    let suffix = "\"schema_cid\":\"" +
      @local_table.table_storage_mapping_schema_cid(mapping) +
      "\",\"storage_mapping_cid\":\"" +
      @local_table.table_storage_mapping_cid(mapping) +
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
    reference,
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
      reference,
      8192,
      256,
      8,
    )
    is Err(@publication_host.ForeignInput),
  )
  // A private Artifact cannot satisfy an ordinary member or the Result
  // namespace of the Manifest, even when names and content are equal.
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
    is Err(@publication_host.DuplicateTableInput),
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
  let ordinary_artifact = @publication_host.issue_source_free_client_effect_local_result_artifact(
    prepared, inputs, 1, ordinary, completed, bridge, ordinary_preparation, ordinary_definition,
    invocation, ordinary_receipt, retention, admission, run_definition, run_invocation,
    observation, 65536, 4096, 32,
  ).unwrap()
  let ordinary_identity = @publication_host.issue_source_free_client_effect_local_identity(
    prepared, inputs, 1, ordinary_artifact, 100, 65536, 4096, 32,
  ).unwrap()
  if repeated {
    let second = @strategy.captured_effect_table_input_at(inputs, 2).unwrap()
    assert_true(@strategy.captured_effect_inputs_share_view(inputs, 0, 2))
    assert_true(@strategy.captured_effect_inputs_share_view(inputs, 2, 0))
    assert_false(@strategy.captured_effect_inputs_share_view(inputs, 1, 2))
    assert_true(
      @strategy.captured_table_input_borrows_share_view(
        borrow,
        @strategy.captured_effect_table_input_borrow(second),
      ),
    )
    let second_definition = @publication_host.issue_captured_client_effect_local_table_definition(
      prepared, inputs, 2, 4096, 32, 8,
    ).unwrap()
    assert_eq(
      @publication_host.client_effect_local_table_definition_cid(
        second_definition,
      ),
      @publication_host.client_effect_local_table_definition_cid(definition),
    )
    // One semantic Artifact serves the same checked view, not a copied payload.
    // The second member still has a separate pin and a distinct Effect identity.
    let second_identity = @publication_host.issue_source_free_client_effect_local_identity(
      prepared, inputs, 2, artifact, 100, 65536, 4096, 32,
    ).unwrap()
    assert_true(
      @publication_host.client_effect_local_identity_matches(
        second_identity, prepared, 2, artifact,
      ),
    )
  }
  let mut out_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    if @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(
          @strategy.captured_effect_local_result_borrow(result),
        ),
      ) ==
      "out" {
      out_index = index
    }
  }
  assert_true(out_index >= 0)
  let out_result = @strategy.captured_effect_local_result_at(inputs, out_index).unwrap()
  let (out_preparation, out_receipt) = local_effect_export_receipt(
    output,
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(out_result),
    ),
  )
  let out_export = @strategy.bind_captured_effect_local_result_managed_export(
    inputs, out_index, completed, bridge, out_preparation,
  ).unwrap()
  let out_definition = @publication_host.issue_client_effect_local_result_definition(
    prepared, 0, "out", 4096, 32, 8,
  ).unwrap()
  let out_artifact = @publication_host.issue_source_free_exported_client_effect_local_result_artifact(
    prepared, inputs, out_export, out_definition, invocation, out_receipt, retention,
    admission, run_definition, run_invocation, observation, 65536, 4096, 32,
  ).unwrap()
  let all_artifacts = [out_artifact, ordinary_artifact, artifact]
  let manifest = @publication_host.issue_client_effect_local_manifest(
    prepared, invocation, all_artifacts, 65536, 4096, 32,
  ).unwrap()
  let result_artifact_cid = @publication_host.client_effect_local_result_artifact_cid
  let invocation_cid = @publication_host.client_effect_local_invocation_cid(
    invocation,
  )
  // Independent preimage uses both namespaces, including the same authored
  // name. Neither inventory is inferred from the other or from sample rows.
  let prefix = "{\"local_invocation_cid\":\"" +
    invocation_cid +
    "\",\"results\":{\"other\":\"" +
    result_artifact_cid(ordinary_artifact) +
    "\",\"out\":\"" +
    result_artifact_cid(out_artifact) +
    "\"},"
  let suffix = "\"table_inputs\":{\"out\":\"" +
    result_artifact_cid(artifact) +
    "\"},\"unit_definition_cid\":\"" +
    unit_cid +
    "\",\"version\":\"actql-local-result-manifest/0.1\"}"
  let manifest_cid = native_publication_cid(prefix + suffix)
  assert_eq(
    @publication_host.client_effect_local_manifest_cid(manifest),
    manifest_cid,
  )
  assert_eq(
    @publication_host.client_effect_local_manifest_json(manifest),
    prefix + "\"self_cid\":\"" + manifest_cid + "\"," + suffix,
  )
  assert_eq(
    @publication_host.client_effect_local_manifest_json(
      @publication_host.issue_client_effect_local_manifest(
        prepared,
        invocation,
        [artifact, ordinary_artifact, out_artifact],
        65536,
        4096,
        32,
      ).unwrap(),
    ),
    @publication_host.client_effect_local_manifest_json(manifest),
  )
  assert_true(
    @publication_host.client_effect_local_manifest_matches(
      manifest, prepared, invocation, all_artifacts,
    ),
  )
  assert_false(
    @publication_host.client_effect_local_manifest_matches(
      manifest,
      prepared,
      invocation,
      [out_artifact, ordinary_artifact],
    ),
  )
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared,
      invocation,
      [out_artifact, ordinary_artifact],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.IncompleteTableInputs),
  )
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared,
      invocation,
      [artifact, ordinary_artifact],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.IncompleteResults),
  )
  assert_true(
    @publication_host.issue_client_effect_local_manifest(
      prepared,
      invocation,
      [out_artifact, ordinary_artifact, artifact, artifact],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.DuplicateTableInput),
  )
  if repeated {
    // Close each occurrence without replaying compute, dropping the common
    // producer, or treating inventory deduplication as physical release.
    @execution.cancel_completed_relation_export_receipt(ordinary_receipt)
    @execution.cancel_completed_result_relation_export(ordinary_preparation)
    |> ignore
    @execution.cancel_completed_relation_export_receipt(out_receipt)
    @execution.cancel_completed_result_relation_export(out_preparation)
    |> ignore
    assert_true(@strategy.release_captured_effect_inputs(inputs))
    assert_false(@strategy.release_captured_effect_inputs(inputs))
    assert_false(@strategy.captured_table_input_borrow_available(borrow))
    @execution.cancel_completed_relation_export_receipt(receipt)
    @execution.close_managed_publication_bridge(bridge)
    available.val = false
    (operations.cleanup_refresh)() |> ignore
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    return
  }
  let (preview_wire, preview, authoring_cid) = private_table_test_preview(
    prepared,
    admission,
    run_definition,
    run_invocation,
    artifact,
    ordinary_artifact,
    identity,
    ordinary_identity,
    @publication_host.client_table_input_operation(table_input),
    scope,
  )
  let run_cid = @publication.publication_contract_identity(run_definition)
  let source_binding = @publication.effect_preview_member_source_binding_cid(
    preview, 0,
  ).unwrap()
  let store_authority = native_publication_cid("private-table-store-authority")
  let logical_cid = @execution.logical_relation_cid(
    @execution.completed_relation_export_identity(receipt),
  )
  let schema_cid = @execution.relation_schema_cid(
    @execution.completed_relation_export_schema_identity(receipt),
  )
  let physical_artifact = @publication.issue_effect_table_input_artifact(
    run_invocation,
    retention,
    "out",
    source_binding,
    store_authority,
    logical_cid,
    schema_cid,
    if empty {
      0
    } else {
      1
    },
    65536,
    4096,
    32,
  ).unwrap()
  let semantic_artifact = @publication.admit_publication_contract(
    "result_artifact",
    @publication_host.client_effect_local_result_artifact_json(artifact),
    65536,
    4096,
    32,
  ).unwrap()
  let physical_source = @publication.admit_captured_effect_source_from_table_input(
    preview, 0, run_invocation, physical_artifact, semantic_artifact, store_authority,
  ).unwrap()
  assert_true(
    @publication_host.client_effect_local_source_matches(
      prepared, inputs, 0, manifest, invocation, artifact, physical_source,
    ),
  )
  assert_false(
    @publication_host.client_effect_local_source_matches(
      prepared, inputs, 1, manifest, invocation, artifact, physical_source,
    ),
  )
  assert_false(
    @publication_host.client_effect_local_source_matches(
      prepared, inputs, 0, manifest, invocation, ordinary_artifact, physical_source,
    ),
  )
  assert_true(
    @publication.captured_effect_source_matches_table_input_facts(
      physical_source, semantic_artifact, "out",
    ),
  )
  assert_false(
    @publication.captured_effect_source_matches_result_facts(
      physical_source, semantic_artifact, "out",
    ),
  )
  assert_true(
    @publication.admit_captured_effect_source_from_result(
      preview, 0, run_invocation, physical_artifact, semantic_artifact, store_authority,
    )
    is Err(_),
  )
  let ordinary_physical = @publication.issue_effect_source_artifact(
    run_invocation,
    retention,
    "out",
    source_binding,
    store_authority,
    logical_cid,
    schema_cid,
    if empty {
      0
    } else {
      1
    },
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    @publication.admit_captured_effect_source_from_table_input(
      preview, 0, run_invocation, ordinary_physical, semantic_artifact, store_authority,
    )
    is Err(_),
  )
  let ordinary_semantic = @publication.admit_publication_contract(
    "result_artifact",
    @publication_host.client_effect_local_result_artifact_json(
      ordinary_artifact,
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let ordinary_source_artifact = @publication.issue_effect_source_artifact(
    run_invocation,
    retention,
    "other",
    @publication.effect_preview_member_source_binding_cid(preview, 1).unwrap(),
    store_authority,
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(ordinary_receipt),
    ),
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(ordinary_receipt),
    ),
    if empty {
      0
    } else {
      1
    },
    65536,
    4096,
    32,
  ).unwrap()
  let ordinary_source = @publication.admit_captured_effect_source_from_result(
    preview, 1, run_invocation, ordinary_source_artifact, ordinary_semantic, store_authority,
  ).unwrap()
  let table_evidence = @publication_host.admit_client_effect_local_source_evidence(
    prepared, inputs, 0, manifest, invocation, artifact, physical_source, 65536,
    4096, 32,
  ).unwrap()
  let result_evidence = @publication_host.admit_client_effect_local_source_evidence(
    prepared, inputs, 1, manifest, invocation, ordinary_artifact, ordinary_source,
    65536, 4096, 32,
  ).unwrap()
  assert_true(
    @publication.captured_effect_source_matches_preview(
      preview, 0, run_invocation, physical_source, table_evidence, store_authority,
      65536, 4096, 32,
    ),
  )
  assert_true(
    @publication.captured_effect_source_matches_preview(
      preview, 1, run_invocation, ordinary_source, result_evidence, store_authority,
      65536, 4096, 32,
    ),
  )
  assert_false(
    @publication.captured_effect_source_matches_preview(
      preview, 0, run_invocation, physical_source, result_evidence, store_authority,
      65536, 4096, 32,
    ),
  )
  // Values inputs have no acquired/imported dependency. Do not fabricate
  // Source observations to make the private source appear recoverable.
  assert_true(
    @publication.admit_captured_effect_source_dependencies(
      [table_evidence, result_evidence],
      "[]",
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  assert_true(
    @publication_host.client_effect_local_source_matches(
      prepared, inputs, 1, manifest, invocation, ordinary_artifact, ordinary_source,
    ),
  )
  assert_true(
    @publication.captured_effect_source_inventory_from_artifacts_valid(
      preview,
      [0, 1],
      [physical_artifact, ordinary_source_artifact],
      [semantic_artifact, ordinary_semantic],
    ),
  )
  assert_false(
    @publication.captured_effect_source_inventory_from_artifacts_valid(
      preview,
      [1, 0],
      [physical_artifact, ordinary_source_artifact],
      [semantic_artifact, ordinary_semantic],
    ),
  )
  assert_eq(
    @publication.effect_preview_member_relation_source(preview, 0),
    Some(@publication.TableInput("out")),
  )
  assert_eq(
    @publication.effect_preview_member_relation_source(preview, 1),
    Some(@publication.Result("other")),
  )
  assert_true(
    @publication_host.check_source_free_client_effect_preview_identities(
      prepared,
      inputs,
      preview_wire,
      run_cid,
      authoring_cid,
      [identity, ordinary_identity],
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  assert_true(
    @publication_host.check_source_free_client_effect_preview_identities(
      prepared,
      inputs,
      preview_wire,
      run_cid,
      authoring_cid,
      [ordinary_identity],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.MissingIdentity),
  )
  let plan_limits : @stage_results.EffectPlanIdentityLimits = {
    max_fields: 100,
    max_work: 10000,
    max_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
  let bound = @program_check.bind_effect_program_run_preview(
    @strategy.captured_effect_run_owner(effect_run),
    run_invocation,
    0,
    preview,
    10000,
    plan_limits,
  ).unwrap()
  let captured_preview = @strategy.bind_captured_effect_preview_inputs(
    effect_run, inputs, bound, 10000,
  ).unwrap()
  assert_true(
    @strategy.captured_effect_preview_inputs_available(captured_preview),
  )
  assert_true(
    @strategy.captured_effect_preview_input_at(captured_preview, 0) is None,
  )
  assert_true(
    physical_equal(
      @strategy.captured_effect_preview_table_input_at(captured_preview, 0).unwrap(),
      table,
    ),
  )
  assert_true(
    @strategy.captured_effect_preview_table_input_at(captured_preview, 1)
    is None,
  )
  let table_preview = @publication_host.bind_client_table_preview(
    table_input, captured_preview, 0,
  ).unwrap()
  assert_true(
    @strategy.captured_effect_preview_plan_terminal(
      captured_preview, 0, 100, 10000,
    )
    is Ok(None),
  )
  assert_true(
    @publication_host.client_table_preview_input_available(table_preview),
  )
  assert_true(
    @publication_host.bind_client_table_preview(
      table_input, captured_preview, 1,
    )
    is Err(@publication_host.Unavailable),
  )
  let swapped = preview_wire.replace(
    old="\"source_table_input\":\"out\"",
    new="\"source_result\":\"out\"",
  )
  let (swapped_wire, swapped_preview) = @publication.author_effect_preview_semantic_wire(
    swapped, run_cid, authoring_cid, 65536, 4096, 32,
  ).unwrap()
  assert_true(
    @program_check.bind_effect_program_run_preview(
      @strategy.captured_effect_run_owner(effect_run),
      run_invocation,
      0,
      swapped_preview,
      10000,
      plan_limits,
    )
    is Err(
      @program_check.Static(
        @program_check.Inventory(
          @stage_results.Inventory(@stage_results.SourceMismatch("save"))
        )
      )
    ),
  )
  assert_true(
    @publication_host.check_source_free_client_effect_preview_identities(
      prepared,
      inputs,
      swapped_wire,
      run_cid,
      authoring_cid,
      [identity, ordinary_identity],
      65536,
      4096,
      32,
    )
    is Err(@publication_host.ForeignPreview),
  )
  @execution.cancel_completed_relation_export_receipt(ordinary_receipt)
  @execution.cancel_completed_relation_export_receipt(out_receipt)
  @execution.cancel_completed_result_relation_export(out_preparation) |> ignore
  @execution.cancel_completed_result_relation_export(ordinary_preparation)
  |> ignore
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.captured_effect_inputs_share_view(inputs, 0, 0))
  assert_true(
    @publication_host.issue_source_free_captured_client_effect_local_invocation(
      prepared, inputs, 0, 4096, 32, 8,
    )
    is Err(@publication_host.ForeignCapturedInput),
  )
  assert_false(
    @strategy.captured_effect_preview_inputs_available(captured_preview),
  )
  assert_false(
    @publication_host.client_table_preview_input_available(table_preview),
  )
  assert_true(@strategy.captured_effect_table_input_at(inputs, 0) is None)
  assert_false(
    @publication_host.client_effect_local_source_matches(
      prepared, inputs, 1, manifest, invocation, ordinary_artifact, ordinary_source,
    ),
  )
  assert_false(
    @publication_host.client_effect_local_source_matches(
      prepared, inputs, 0, manifest, invocation, artifact, physical_source,
    ),
  )
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
fn private_table_test_preview(
  prepared : @publication_host.PreparedClientEffectComputation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  table_artifact : @publication_host.ClientEffectLocalResultArtifact,
  result_artifact : @publication_host.ClientEffectLocalResultArtifact,
  table_identity : @publication_host.ClientEffectLocalIdentity,
  result_identity : @publication_host.ClientEffectLocalIdentity,
  operation : @effect.TableOperation,
  scope : @request_scope.LogicalRequestScope,
) -> (String, @publication.EffectPreviewIdentity, String) raise {
  let definition = @publication_host.prepared_client_effect_computation_definition_cid(
    prepared,
  )
  let authoring_body = "{\"annotations\":[],\"program_definition_cid\":\"" +
    definition +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  let authoring = native_publication_cid(authoring_body)
  let placeholder = native_publication_cid("private-table-preview-placeholder")
  let correlation = "\"" + @effect.table_operation_cid(operation) + "\""
  let members : Array[String] = []
  for index in 0..<2 {
    let id = if index == 0 { "save" } else { "copy" }
    let (_, _, kind, target, mapping, mapping_cid, _, failure, private_source) = @publication_host.client_effect_member_descriptor(
      prepared, 0, id, 100,
    ).unwrap()
    assert_eq(private_source, if index == 0 { Some("out") } else { None })
    let artifact = if index == 0 { table_artifact } else { result_artifact }
    let identity = if index == 0 { table_identity } else { result_identity }
    let row = "{\"after\":{\"state\":\"not_applicable\"},\"before\":{\"state\":\"not_applicable\"},\"intended_changes\":{\"state\":\"present\",\"value\":" +
      @effect.table_operation_json(operation) +
      "},\"row_idempotency_key\":\"" +
      placeholder +
      "\",\"row_preview_cid\":\"" +
      placeholder +
      "\",\"target_guard\":{\"state\":\"not_applicable\"},\"target_row_identity\":" +
      correlation +
      "}"
    members.push(
      "{\"approval\":\"required\",\"authority_scope_cid\":\"" +
      placeholder +
      "\",\"capability_evidence_cid\":\"" +
      placeholder +
      "\",\"changes\":" +
      (if index == 0 { "[" + row + "]" } else { "[]" }) +
      ",\"count\":" +
      (if index == 0 { "1" } else { "0" }) +
      ",\"effect_id\":\"" +
      id +
      "\",\"effect_identity_cid\":\"" +
      @publication_host.client_effect_local_identity_cid(identity) +
      "\",\"effect_kind\":\"" +
      kind +
      "\",\"effect_member_preview_cid\":\"" +
      placeholder +
      "\",\"executed\":false,\"mapping\":\"" +
      mapping +
      "\",\"max_items\":1,\"on_item_failure\":\"" +
      failure +
      "\",\"preview_strength\":\"blind\",\"required_permissions\":[\"scope:create\"],\"resolved_mapping_contract_cid\":\"" +
      mapping_cid +
      "\",\"result_artifact_cid\":\"" +
      @publication_host.client_effect_local_result_artifact_cid(artifact) +
      "\",\"row_order\":" +
      (if index == 0 { "[\"" + placeholder + "\"]" } else { "[]" }) +
      ",\"source_binding_cid\":\"" +
      placeholder +
      "\"," +
      (if index == 0 {
        "\"source_table_input\":\"out\""
      } else {
        "\"source_result\":\"other\""
      }) +
      ",\"target\":\"" +
      target +
      "\",\"write_footprint\":{\"kind\":\"collection\",\"provider_boundary_cid\":\"" +
      placeholder +
      "\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[],\"resource_identity_scheme_cid\":\"" +
      placeholder +
      "\",\"resource_kind\":\"Table\"}}",
    )
  }
  let run_cid = @publication.publication_contract_identity(run_definition)
  let raw = "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"" +
    authoring +
    "\",\"program_definition_cid\":\"" +
    definition +
    "\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"" +
    @publication_host.prepared_client_effect_computation_environment_cid(
      prepared,
    ) +
    "\",\"compiled_plan_cid\":\"" +
    @publication.run_publication_compiled_plan_cid(admission) +
    "\",\"effect_preview_cid\":\"" +
    placeholder +
    "\",\"effects\":[" +
    members.join(",") +
    "],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"" +
    @publication.publication_contract_identity(invocation) +
    "\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"" +
    definition +
    "\",\"program_semantics_cid\":\"" +
    @publication_host.prepared_client_effect_computation_semantics_cid(prepared) +
    "\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"" +
    run_cid +
    "\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}"
  let (semantic_wire, semantic) = @publication.author_effect_preview_semantic_wire(
    raw, run_cid, authoring, 65536, 4096, 32,
  ).unwrap()
  let key = @effect.prepare_effect_dispatch_key(
    scope,
    @publication.effect_preview_semantic_identity(semantic),
    correlation,
    73,
    1,
    1,
  ).unwrap()
  let wire = @publication.complete_effect_preview_dispatch_keys(
    semantic_wire,
    [[@effect.effect_dispatch_key_cid(key)], []],
    run_cid,
    authoring,
    65536,
    4096,
    32,
  ).unwrap()
  let preview = @publication.admit_effect_preview_identity(
    wire, run_cid, authoring, 65536, 4096, 32,
  ).unwrap()
  (wire, preview, authoring)
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

///|
test "checked Effect capture inventories a repeated private Table input once but holds both occurrences" {
  verify_captured_private_table_input(false, repeated=true)
}
