///|
// Explicitly authored Program/installation copied from the retained submission
// fixture. These Native definitions are compiler evidence until executed.
let local_effect_prefix_fixture_document : String =
  #|{"id":"native-effect","results":{"published":{"from":{"result":"out","stage":"source"}}},"stages":[{"effects":{"save":{"create":{"from":{"result":"out"},"mapping":"mapping:crm.account.v1","target":"connector://crm/account"}}},"id":"source","inputs":{},"results":{"out":{"fields":["value"],"from":"selected"}},"steps":[{"as":"selected","values":{"rows":[{"value":"e\u0301\r\n"}],"schema":{"value":{"nullable":false,"type":"string"}}}}]}],"version":"actql/0.1"}

///|
let local_effect_prefix_fixture_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:1be9426a9b8809a531aae1c2cac2bfe7bef35b4fccff982c52da4a4de350190b","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn local_effect_prefix_fixture_preparation() -> @local_host.NativeClientSubmittedPreparation {
  let environment = @run_host.admit_client_check_environment(
    local_effect_prefix_fixture_environment_wire,
    "sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    local_effect_prefix_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  @local_host.prepare_native_client_submitted_program(
    intent,
    environment,
    None,
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap()
}

///|
fn local_effect_prefix_fixture_original(
  preparation : @local_host.NativeClientSubmittedPreparation,
  request_id? : String = "original-request",
) -> LocalEffectFirstCompilation raise ClientStop {
  local_effect_first_compilation(
    preparation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "local-test",
    request_id,
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  )
}

///|
test "CLI first Effect compilation retains original create profile and exact normalization journal" {
  let preparation = local_effect_prefix_fixture_preparation()
  let original = local_effect_prefix_fixture_original(preparation)
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()
  let bound = @run_host.bind_client_effect_compiled_run(
    @run_host.client_effect_compilation_owner(original.allowed.compilation),
    original.allowed,
    original.definition,
  ).unwrap()
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) else {
    fail("missing original preparation")
  }
  assert_true(
    physical_equal(
      prepared,
      @run_host.client_effect_compilation_owner(original.allowed.compilation),
    ),
  )
  assert_eq(materials.request, Some(original.request))
  assert_true(
    physical_equal(
      @run_host.prepared_client_effect_run_computation(bound),
      prepared,
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      @run_host.restore_client_effect_run_normalization(materials).unwrap(),
    ),
    "{\"entries\":[],\"journal_cid\":\"sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087\",\"rule_catalog_cid\":\"sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38\",\"version\":\"actql-normalization-journal/0.1\"}",
  )
}

///|
// This executes the CLI's first compiled Run with the existing Core fixture
// Ledger. It does not install normal funding, accept a journal Run or authorize
// an Effect. Public contract originals come from the bundled asset admission.
test "CLI first Effect binding remains the nominal owner through Local Values Compute and capture" {
  let original = local_effect_prefix_fixture_original(
    local_effect_prefix_fixture_preparation(),
  )
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()
  let bound = @run_host.bind_client_effect_compiled_run(
    @run_host.client_effect_compilation_owner(original.allowed.compilation),
    original.allowed,
    original.definition,
  ).unwrap()
  let assets = @run_host.client_local_product_assets()
  let values = assets.values
  let fragment = Some(assets.fragment)
  let registry = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    values,
    fragment,
    None,
  ).unwrap()
  let capacity = @local_values.client_effect_local_ledger_limits(
    materials.prepared,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let captured = @run_host.open_prepared_source_free_client_effect_run(
    bound, capacity,
  ).unwrap()
  let dag = @strategy.captured_effect_run_dag(captured)
  defer {
    @strategy.stop_captured_dag(dag)
    @strategy.close_captured_task_output(dag, 0)
    @strategy.refresh_captured_retention(dag)
  }
  // Equal canonical inputs cannot replace this nominal first binding.
  let replacement = @run_host.bind_client_effect_compiled_run(
    materials.prepared,
    original.allowed,
    original.definition,
  ).unwrap()
  assert_true(
    @local_values.configure_source_free_effect_local_retained_host(
      replacement,
      captured,
      registry,
      values,
      fragment,
      None,
    )
    is None,
  )
  assert_false(@strategy.captured_task_completed(dag, 0))
  let setup = @local_values.configure_source_free_effect_local_retained_host(
    bound,
    captured,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let execution = @local_values.execute_source_free_values_guarded(
    setup,
    64,
    1000,
    () => true,
  ).unwrap()
  defer execution.close() |> ignore
  assert_eq(execution.rows().unwrap(), ["{\"value\":\"é\\r\\n\"}"])
  assert_true(@strategy.captured_task_completed(dag, 0))
  let inputs = @strategy.pin_captured_effect_sources(captured, 1).unwrap()
  defer @strategy.release_captured_effect_inputs(inputs) |> ignore
  assert_eq(@strategy.captured_effect_inputs_count(inputs), 1)
  let input = @strategy.captured_effect_input_at(inputs, 0).unwrap()
  assert_true(
    @strategy.captured_any_result_borrow_matches_managed(
      @strategy.captured_effect_input_borrow(input),
      execution.completed_output(),
    ),
  )
  assert_eq(materials.request, Some(original.request))
}

///|
test "CLI first Effect materials reject replacement physical compilation with identical input" {
  let original = local_effect_prefix_fixture_original(
    local_effect_prefix_fixture_preparation(),
  )
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()
  let replacement = local_effect_prefix_fixture_original(
    local_effect_prefix_fixture_preparation(),
  )
  assert_true(
    @run_host.bind_prepared_client_effect_original_materials(
      replacement.allowed,
      replacement.definition,
      original.issued,
      request=Some(replacement.request),
    )
    is Err(_),
  )
  let same = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()
  assert_true(physical_equal(same.compilation, materials.compilation))
  assert_eq(
    @run_host.client_effect_normalization_materials_cid(same),
    @run_host.client_effect_normalization_materials_cid(materials),
  )
}

///|
test "CLI first Effect materials reject another original request without changing custody" {
  let preparation = local_effect_prefix_fixture_preparation()
  let original = local_effect_prefix_fixture_original(preparation)
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) else {
    fail("missing original preparation")
  }
  let foreign = @run_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "other-request",
    @run_host.source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(
    @run_host.bind_prepared_client_effect_original_materials(
      original.allowed,
      original.definition,
      original.issued,
      request=Some(foreign),
    )
    is Err(_),
  )
  assert_eq(materials.request, Some(original.request))
}

///|
test "CLI first Effect compilation refuses invalid lifetime before journal accept or Source open" {
  let refused = try {
    local_effect_first_compilation(
      local_effect_prefix_fixture_preparation(),
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "local-test",
      "original-request",
      "not-a-time",
      "2099-01-01T00:00:00.000Z",
    )
    |> ignore
    None
  } catch {
    ClientStop(reason) => Some(reason)
  }
  assert_eq(refused, Some("LocalEffectRunDefinitionNotReady"))
}

///|
test "Native Host Source Work retains its actual typed authorization refusal" {
  // Compile the actual Host open method, not a future uninstalled CLI adapter.
  // No Host, physical Source or Provider is opened by this definition.
  let caller = fn(
    host : @local_host.NativeLocalHostConnection,
    crypto : @local_crypto.Library,
    principal : String,
    connection : String,
    request : @run_host.ClientRequestIdentity,
    allowed : @run_host.ClientEffectAllowedRun,
    definition : @publication.PublicationContract,
    materials : @run_host.ClientEffectRunMaterials,
    configuration : @source_owner.ResidentSourceComputeConfiguration,
    occurrence : String,
    current_time : () -> String,
  ) {
    host.open_effect_source_work(
      crypto, principal, connection, request, allowed, definition, materials, configuration,
      occurrence, current_time,
    )
  }
  caller |> ignore
  let issue = @local_host.NativeClientSourceWorkIssue::AuthorizationDenied
  assert_true(issue is @local_host.AuthorizationDenied)
}

///|
// The update installation preimages were independently hashed with Python
// hashlib. Neither journal expectation is derived from the tested compiler.
let local_effect_prefix_update_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:de7cfc6d9aa91109ea99c14a77c22fbe49c94e49d6ff0d2fefd49a9904831288","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:c99f6697a8b40c16a418a156177be2a6144be3ba5ebbc36020c819789d021cd4","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"update","permissions":["scope:update"],"selector_class":"ids","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let local_effect_prefix_update_document : String =
  #|{"id":"native-update","results":{"published":{"from":{"result":"out","stage":"source"}}},"stages":[{"effects":{"save":{"update":{"from":{"result":"out"},"id":"id","mapping":"mapping:crm.account.v1","set":{"Name":{"field":"value"}},"target":"connector://crm/account"}}},"id":"source","inputs":{},"results":{"out":{"fields":["id","value"],"from":"selected"}},"steps":[{"as":"selected","values":{"rows":[{"id":"original-id","value":1}],"schema":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"number"}}}}]}],"version":"actql/0.1"}

///|
test "CLI first update compilation uses the distinct audited profile without changing create identity" {
  let environment = @run_host.admit_client_check_environment(
    local_effect_prefix_update_environment,
    "sha256:de7cfc6d9aa91109ea99c14a77c22fbe49c94e49d6ff0d2fefd49a9904831288",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    local_effect_prefix_update_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = @local_host.prepare_native_client_submitted_program(
    intent,
    environment,
    None,
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let original = local_effect_prefix_fixture_original(preparation)
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      @run_host.restore_client_effect_run_normalization(materials).unwrap(),
    ),
    "{\"entries\":[],\"journal_cid\":\"sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d\",\"rule_catalog_cid\":\"sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468\",\"version\":\"actql-normalization-journal/0.1\"}",
  )
}
