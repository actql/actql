///|
// Actual checked Query/acquisition/provider DATA only. These two mutation
// controls do not admit a physical Account/Read/Work or establish cleanup ACK.
fn relation_snapshot_fixture_declaration() -> @rows.RowDeclaration {
  @rows.generate_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "string", nullable: false, },
          { name: "value", value_type: "number", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
}

///|
// Environment sections are ordered by each complete canonical member CID.
// This creates checking inputs, never an expected capture or physical result.
fn relation_snapshot_fixture_members(bodies : Array[String]) -> Json raise {
  let ordered = bodies.map(wire => {
    let body = @canonical.from_json(@json.parse(wire), 100000, 100, 1000000)
    (@canonical.cid_value(body, 1000000, 100000, 100), @json.parse(wire))
  })
  ordered.sort_by((left, right) => left.0.compare(right.0))
  Json::array(ordered.map(entry => entry.1))
}

///|
fn relation_snapshot_fixture_environment(
  declaration : @rows.RowDeclaration,
) -> (String, String) raise {
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(
    declaration,
  )
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "connector_manifest": {
      "version": "actql-connectors/0.1",
      "connectors": [@json.parse(declaration.manifest_entry)],
    },
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "contract_registry": relation_snapshot_fixture_members(
      declaration.contracts,
    ),
    "source_views": relation_snapshot_fixture_members(declaration.view_bodies),
    "schema_snapshots": relation_snapshot_fixture_members(schemas),
    "connector_capabilities": relation_snapshot_fixture_members(capabilities),
    "command_contracts": [],
    "mapping_contracts": [],
    "model_task_contracts": [],
    "host_policy_profile": {
      "capacity": {
        "version": "actql-capacity-host-policy/0.1",
        "max_aggregate_array_items": 10000,
        "max_artifact_bytes": 10000,
        "max_artifact_rows": 10000,
        "max_effect_items": 10000,
        "max_graph_input_edges": 10000,
        "max_graph_input_nodes": 10000,
        "max_graph_output_rows": 10000,
        "max_graph_paths": 10000,
        "max_infer_items": 10000,
        "max_model_input_tokens_per_item": 10000,
        "max_model_request_bytes_per_item": 10000,
        "max_model_total_duration_ms": 10000,
        "max_nested_value_bytes": 10000,
        "max_nested_value_depth": 10000,
        "max_relation_output_rows": 10000,
        "max_temporal_matches_per_key": 10000,
        "max_temporal_output_rows": 10000,
      },
    },
  }
  let canonical = @canonical.from_json(body, 100000, 100, 1000000)
  let cid = @canonical.cid_value(canonical, 1000000, 100000, 100)
  let enveloped = @canonical.object_with_string_field(
    canonical, "evidence_bundle_cid", cid,
  ).unwrap()
  (@canonical.stringify_value(enveloped, 1000000, 100000, 100), cid)
}

///|
fn relation_snapshot_fixture_logical() -> (
  @rows.RowDeclaration,
  @planning.QueryRequirement,
  @rows.RowAcquisition,
) raise {
  let declaration = relation_snapshot_fixture_declaration()
  let (wire, cid) = relation_snapshot_fixture_environment(declaration)
  let environment = @host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"native-file-capture","stages":[{"id":"acquire","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"filter":"value > 1"},{"select":["id","value"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","value"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"value > 0"},{"select":["id","value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let assets = @host.client_local_product_assets()
  let contracts = @local.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let requirement = @local.prepare_local_query_requirement(
    prepared,
    0,
    0,
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let acquisition = @rows.prepare_row_acquisition(
    declaration, requirement, relation_snapshot_fixture_query_contract, relation_snapshot_fixture_evidence_contract,
  ).unwrap()
  (declaration, requirement, acquisition)
}

///|
let relation_snapshot_fixture_query_contract : String = "{\"version\":\"actql-query-acquisition-contract/0.1\",\"scope\":\"exclusive_finite_relation_scan_filter_select\",\"dependencies\":{\"canonical_value_contract\":{\"path\":\"spec/contracts/actql-protocol-schemas.json\",\"pointer\":\"/schemas/canonical_value_contract\",\"cid\":\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"},\"consumer_capacity\":{\"path\":\"spec/contracts/actql-consumer-capacity.json\",\"pointer\":\"\",\"cid\":\"sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f\"}},\"schemas\":{\"requirement\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"owner\",\"source_ref\",\"source_contract_cid\",\"input_contract_cid\",\"output_contract_cid\",\"request\",\"parameter_values_cid\",\"filter\",\"select\",\"source_validation\",\"source_order_cid\",\"logical_guards\"],\"properties\":{\"version\":{\"const\":\"actql-query-acquisition/0.1\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"input_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"output_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"request\":{\"type\":\"object\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"expression_cid\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"expression_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"select\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"fields\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"fields\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"input\",\"output\"],\"properties\":{\"input\":{\"type\":\"string\",\"minLength\":1},\"output\":{\"type\":\"string\",\"minLength\":1}}}}}},\"source_validation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope\",\"fields\"],\"properties\":{\"scope\":{\"const\":\"selected_scan\"},\"fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true}}},\"source_order_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"logical_guards\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"max_rows\",\"max_value_bytes\"],\"properties\":{\"max_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"max_value_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"},\"completed_observation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"requirement_cid\",\"owner\",\"source_ref\",\"source_contract_cid\",\"parameter_values_cid\",\"resolved_request_cid\",\"snapshot\",\"actual_access\",\"coverage\",\"output\",\"retention\"],\"properties\":{\"version\":{\"const\":\"actql-query-observation/0.1\"},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"resolved_request_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"coverage\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"complete\",\"source_validation_evidence_cid\",\"filter_evidence_cid\",\"select_evidence_cid\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"complete\":{\"const\":true},\"source_validation_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"select_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"retention\":{\"const\":\"process\"}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}},\"semantics\":{\"owner\":\"program_source_cid_is_authority_bearing_program_definition_cid_not_program_semantics_or_source_text_hash\",\"query_time_owner\":\"declared_query_time_dependency_requires_original_admitted_run_definition_cid_in_requirement_and_completed_observation_owner_with_same_nominal_context_and_saved_run_no_resample_no_grant\",\"derivation\":\"checked_exclusive_scan_filter_select_without_backend_cost_or_placement\",\"capture\":\"completed_select_output_before_any_consumer\",\"identity\":\"sha256_of_canonical_json_utf8_entire_body_no_self_cid\",\"request_values\":\"bound_wire_values_no_reinterpretation_of_business_param_or_literal\",\"parameter_identity\":\"existing_typed_parameter_values_projection_of_used_request_and_query_names\",\"source_validation\":\"all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter\",\"demand\":\"existing_checked_expression_demand_without_eager_undemanded_evaluation\",\"native\":\"preserve_mandatory_admission_and_demanded_failures_before_projection\",\"logical_guards\":\"max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots\",\"physical_budget\":\"actual_received_bytes_rows_and_retention_independent_of_logical_output\",\"failure\":\"atomic_no_success_capture_or_consumer_on_failure_or_cancellation\",\"evidence\":\"verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only\",\"snapshot\":\"source_specific_no_universal_snapshot_token_or_isolation_requirement\",\"retention\":\"same_process_immutable_completed_observation_not_durable_run_or_recovery\",\"invocation\":\"existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only\"}}"

///|
let relation_snapshot_fixture_evidence_contract : String = "{\"version\":\"actql-query-process-evidence-contract/0.1\",\"dependencies\":{\"query_acquisition\":{\"path\":\"spec/contracts/actql-query-acquisition.json\",\"pointer\":\"\",\"cid\":\"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc\"}},\"schemas\":{\"record\":{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"issuer\",\"attempt\",\"requirement_cid\",\"role\",\"snapshot\",\"scan_scope_cid\",\"actual_access\",\"output\"],\"properties\":{\"version\":{\"const\":\"actql-query-process-evidence/0.1\"},\"issuer\":{\"type\":\"string\",\"minLength\":1},\"attempt\":{\"type\":\"string\",\"minLength\":1},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"role\":{\"enum\":[\"source_validation\",\"filter\",\"select\"]},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"scan_scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}}}},\"semantics\":{\"preimage\":\"entire_record_canonical_json_utf8_sha256_no_self_cid\",\"authority\":\"authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone\",\"issuance\":\"after_complete_scan_validation_filter_select_limits_and_immutable_output_retention\",\"attempt\":\"host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected\",\"binding\":\"exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles\",\"native\":\"authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns\",\"source_order\":\"null_only_in_this_profile_relative_order_is_not_total_order_evidence\",\"lifetime\":\"same_process_no_deserialization_rehydration_or_durable_capture\",\"host_adapter\":\"host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success\",\"read_view\":\"private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution\",\"access_accounting\":\"engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted\",\"receipt_scope\":\"one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract\",\"scan_failure\":\"invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal\"}}"

///|
fn relation_snapshot_fixture_source() -> NativeRelationFileQuerySource raise {
  let (declaration, _, acquisition) = relation_snapshot_fixture_logical()
  let (selection, limits) = relation_work_capacity_inputs()
  let selection = { ..selection, key_path: Some(["id"]), }
  let provider = @row_file.prepare_native_relation_file_provider(
    declaration, selection, limits,
  ).unwrap()
  { declaration, acquisition, provider, selection, limits, }
}

///|
test "managed File snapshot never copies Sources appended by later current" {
  let original = relation_snapshot_fixture_source()
  let inputs = [original]
  let quoted_count = inputs.length()
  let snapshot = snapshot_managed_relation_file_sources(inputs)
  let current_calls = Ref(0)
  let current = fn() {
    current_calls.val += 1
    inputs.push(original)
    true
  }
  assert_true(current())
  assert_eq(current_calls.val, 1)
  assert_eq(inputs.length(), 2)
  assert_eq(snapshot.length(), quoted_count)
  assert_true(physical_equal(snapshot[0].acquisition, original.acquisition))
  assert_true(physical_equal(snapshot[0].provider, original.provider))
}

///|
test "managed File snapshot keeps quoted paths when current mutates same acquisition" {
  let original = relation_snapshot_fixture_source()
  let inputs = [original]
  let snapshot = snapshot_managed_relation_file_sources(inputs)
  let current_calls = Ref(0)
  let current = fn() {
    current_calls.val += 1
    original.selection.items_path.push("unquoted-child")
    original.selection.key_path.unwrap().push("unquoted-key")
    true
  }
  assert_true(current())
  assert_eq(current_calls.val, 1)
  assert_true(physical_equal(snapshot[0].acquisition, inputs[0].acquisition))
  assert_eq(snapshot[0].selection.items_path, ["items"])
  assert_eq(snapshot[0].selection.key_path, Some(["id"]))
  assert_eq(inputs[0].selection.items_path, ["items", "unquoted-child"])
  assert_eq(inputs[0].selection.key_path, Some(["id", "unquoted-key"]))
}

///|
// Checked original Source/Program DATA only. No Account, physical Source,
// currentness, completion or cleanup acknowledgement is supplied here.
fn whole_publication_task_fixture(
  shared_task : Bool,
) -> @host.PreparedClientProgram raise {
  let declaration = relation_snapshot_fixture_declaration()
  let (wire, cid) = relation_snapshot_fixture_environment(declaration)
  let environment = @host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document = if shared_task {
    (
      #|{"version":"actql/0.1","id":"whole-publication-tasks","stages":[{"id":"joined","inputs":{"left":{"connector":"native-file-fixture","resource":"records"},"right":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"whole-publication-tasks","stages":[{"id":"left","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"right","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"joined","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}
    )
  }
  @host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "Whole publication selects original task coordinates and refuses equal-wire foreign preparation" {
  for shared in [false, true] {
    let prepared = whole_publication_task_fixture(shared)
    let foreign = whole_publication_task_fixture(shared)
    let left = @host.prepare_client_source_acquisition(prepared, 0, 0).unwrap()
    let right = @host.prepare_client_source_acquisition(
      prepared,
      if shared {
        0
      } else {
        1
      },
      if shared {
        1
      } else {
        0
      },
    ).unwrap()
    assert_eq(native_whole_source_publication_task(prepared, left), Some(0))
    assert_eq(
      native_whole_source_publication_task(prepared, right),
      Some(if shared { 0 } else { 1 }),
    )
    assert_true(native_whole_source_publication_task(foreign, left) is None)
    assert_true(native_whole_source_publication_task(foreign, right) is None)
  }
}
