///|
fn client_effect_fixture() -> (
  String,
  @checked.CheckEnvironment,
  ClientEffectComputationLimits,
) {
  let document =
    #|{"version":"actql/0.1","id":"client-effect","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let schema = "{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"string\"},\"Name\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}"
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema))
  let before = "{\"connector_manifest_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"conversions\":[],"
  let after = "\"mapping_ref\":\"mapping:crm.account.v1\",\"minimum_approval\":\"none\",\"permission_rules\":[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}],\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"row_mapping\":{\"Name\":{\"field\":\"value\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://crm/account\",\"target_schema\":" +
    schema +
    ",\"target_schema_identity\":\"" +
    schema_cid +
    "\",\"version\":\"salesforce-v1\",\"writable_fields\":[\"Name\"]}"
  let mapping_cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  let mapping = before +
    "\"mapping_contract_cid\":\"" +
    mapping_cid +
    "\"," +
    after
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[" +
    mapping +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let wire = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let environment = @checked.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let input : @syntax.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    tree: {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
    max_stages: 2,
  }
  let limits : ClientEffectComputationLimits = {
    program: {
      checking: {
        input,
        compilation: {
          work: 10000000,
          artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
          structure: {
            stages: 2,
            steps: 10,
            results: 10,
            parameters: 1,
            bindings: 100,
            slots: 1000,
            references: 1000,
            requirements: 1000,
            tokens: 10000,
          },
          traversal: {
            nodes: 100000,
            depth: 100,
            text_bytes: 10000000,
            string_bytes: 100000,
            name_bytes: 1000000,
            pointer_units: 1000000,
            comparison_pairs: 1000000,
          },
          values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
          policy: { bytes: 10000, nodes: 1000000, depth: 100, },
          patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
        },
      },
      lowering: {
        max_nodes: 100,
        max_references: 100,
        max_work: 100000,
        max_identifier_bytes: 10000,
      },
      max_parameters: 10,
      max_parameter_name_bytes: 1000,
      max_tasks: 2,
      max_graph_work: 10000,
    },
    max_members: 1,
    max_header_work: 100,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
  (document, environment, limits)
}

///|
test "standard Client preparation retains source-free Effect closure" {
  let (document, environment, limits) = client_effect_fixture()
  let prepared = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(value) => value
    Err(_) => fail("Effect computation preparation failed")
  }
  let graph = prepared_client_effect_computation_graph(prepared)
  assert_eq(
    @strategy.graph_task_count(
      @strategy.checked_effect_computation_graph(graph),
    ),
    1,
  )
  assert_true(
    @strategy.graph_program_has_effects(
      @strategy.checked_effect_computation_graph(graph),
    ),
  )
  assert_eq(@strategy.checked_effect_source_count(graph), 1)
  assert_true(@strategy.checked_effect_source_at(graph, 0) is Some(_))
  assert_true(
    physical_equal(
      @strategy.checked_effect_computation_owner(graph),
      prepared_client_effect_computation_candidate(prepared),
    ),
  )
  assert_true(
    prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      limits.program,
    )
    is Err(EffectNotSupported(_)),
  )
  assert_true(
    prepare_client_effect_computation(document, Json, environment, None, [], {
      ..limits,
      max_members: 0,
    })
    is Err(Candidate(_)),
  )
  assert_true(
    prepare_client_effect_computation(
      document.replace(
        old="mapping:crm.account.v1",
        new="mapping:crm.foreign.v1",
      ),
      Json,
      environment,
      None,
      [],
      limits,
    )
    is Err(_),
  )
}

///|
test "checked source-free Effect owner issues its local Invocation" {
  let (document, environment, limits) = client_effect_fixture()
  let prepared = prepare_client_effect_computation(
    document, Json, environment, None, [], limits,
  ).unwrap()
  let issued = issue_source_free_client_effect_local_invocation(
    prepared, 0, 4096, 32, 8,
  ).unwrap()
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(prepared),
  )
  let preimage = "{\"local_contracts_cid\":\"" +
    @checked.unit_contracts_cid(program, 0).unwrap() +
    "\",\"observation_cids\":[],\"policy_cid\":\"" +
    @checked.checked_local_policy_cid(program) +
    "\",\"unit_definition_cid\":\"" +
    @checked.unit_definition_cid(program, 0).unwrap() +
    "\",\"used_values_cid\":\"" +
    @checked.unit_used_values_cid(program, 0).unwrap() +
    "\",\"version\":\"actql-local-computation-semantics/0.1\"}"
  assert_eq(
    client_effect_local_invocation_cid(issued),
    "sha256:" + @sha.hex(@utf8.encode(preimage)),
  )
  assert_true(
    client_effect_local_invocation_json(issued).contains(
      "\"self_cid\":\"" + client_effect_local_invocation_cid(issued) + "\"",
    ),
  )
  assert_true(client_effect_local_invocation_matches(issued, prepared, 0))
  assert_true(!client_effect_local_invocation_matches(issued, prepared, 1))
  let foreign = prepare_client_effect_computation(
    document, Json, environment, None, [], limits,
  ).unwrap()
  assert_true(!client_effect_local_invocation_matches(issued, foreign, 0))
  assert_true(
    issue_source_free_client_effect_local_invocation(prepared, 1, 4096, 32, 8)
    is Err(MissingUnit),
  )
}

///|
test "Effectful Client request uses the common checked intent and scope" {
  let (document, environment, limits) = client_effect_fixture()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let scope = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let input = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let request = prepare_client_effect_request_identity(
    prepared, scope, "write-request", input,
  ).unwrap()
  assert_eq(
    client_request_program_cid(request),
    prepared_client_effect_computation_definition_cid(prepared),
  )
  let body = "{\"caller_input_intent_cid\":\"" +
    input +
    "\",\"parameter_values_cid\":\"" +
    client_request_parameters_cid(request) +
    "\",\"program_definition_cid\":\"" +
    prepared_client_effect_computation_definition_cid(prepared) +
    "\",\"version\":\"actql-logical-request-intent/0.1\"}"
  assert_eq(
    client_request_intent_cid(request),
    "sha256:" + @sha.hex(@utf8.encode(body)),
  )
  let replay = prepare_client_effect_request_identity(
    prepared, scope, "write-request", input,
  ).unwrap()
  assert_true(client_request_identity_relation(request, replay) is SameRequest)
  let changed = prepare_client_effect_request_identity(
    prepared, scope, "write-request", "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  ).unwrap()
  assert_true(
    client_request_identity_relation(request, changed) is ChangedIntent,
  )
  assert_true(
    prepare_client_effect_request_identity(prepared, scope, "", input)
    is Err(InvalidRequestId),
  )
}
