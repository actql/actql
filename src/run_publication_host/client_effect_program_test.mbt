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
  let before = "{\"connector_manifest_cid\":\"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1\",\"conversions\":[],"
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
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd\",\"commands\":[],\"connector_id\":\"crm\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],"
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
test "Effect compilation shares the checked Values Fragment issuer" {
  let (document, environment, limits) = client_effect_fixture()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let graph = prepared_client_effect_computation_graph(prepared)
  let owner = prepared_client_effect_computation_candidate(prepared)
  let sequence_limits : @lower.SequenceLimits = {
    max_steps: 10,
    max_rows: 10,
    max_cells: 10,
    max_bindings: 10,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 10,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }
  let fragment = issue_prepared_client_effect_values_fragment(
    prepared, 0, sequence_limits, 20000, 2000, 100,
  ).unwrap()
  // Independent SHA-256 of the canonical Values pipeline for {value: 1}.
  assert_eq(
    client_values_fragment_logical_cid(fragment),
    "sha256:dbbd1b8a7e0751ce96aece5ac9a85a67eaabfb1ec9e4cf5d86c5a40c64d5afc2",
  )
  assert_eq(client_values_fragment_node_id(fragment), "values_0")
  assert_eq(
    client_values_fragment_output_contract_wire(fragment),
    "{\"additional_properties\":false,\"fields\":{\"value\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
  )
  assert_eq(
    client_values_fragment_wire(
      admit_prepared_client_effect_values_fragment(
        prepared,
        0,
        client_values_fragment_wire(fragment),
        sequence_limits,
        20000,
        2000,
        100,
      ).unwrap(),
    ),
    client_values_fragment_wire(fragment),
  )
  let changed = prepare_client_effect_computation(
    document.replace(old="\"value\":1", new="\"value\":2"),
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    admit_prepared_client_effect_values_fragment(
      changed,
      0,
      client_values_fragment_wire(fragment),
      sequence_limits,
      20000,
      2000,
      100,
    )
    is Err(ClientValuesFragmentAdmissionIssue::MismatchedNode),
  )
  assert_true(
    issue_prepared_client_effect_values_fragment(
      prepared, 1, sequence_limits, 20000, 2000, 100,
    )
    is Err(_),
  )
  assert_true(
    issue_prepared_client_effect_values_fragment(
      prepared, 0, sequence_limits, 1, 2000, 100,
    )
    is Err(_),
  )
  assert_true(
    physical_equal(@strategy.checked_effect_computation_owner(graph), owner),
  )
  assert_eq(@strategy.checked_effect_source_count(graph), 1)
  assert_true(
    @strategy.graph_program_has_effects(
      @strategy.checked_effect_computation_graph(graph),
    ),
  )
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
    document,
    Json,
    environment,
    None,
    [],
    limits,
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
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let replayed = issue_source_free_client_effect_local_invocation(
    foreign, 0, 4096, 32, 8,
  ).unwrap()
  assert_eq(
    client_effect_local_invocation_cid(replayed),
    client_effect_local_invocation_cid(issued),
  )
  assert_true(!client_effect_local_invocation_matches(issued, foreign, 0))
  assert_true(
    issue_source_free_client_effect_local_invocation(prepared, 1, 4096, 32, 8)
    is Err(MissingUnit),
  )
}

///|
test "checked owner issues Unit-local Result Definition only for its Result" {
  let (document, environment, limits) = client_effect_fixture()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let issued = issue_client_effect_local_result_definition(
    prepared, 0, "out", 4096, 16, 4,
  ).unwrap()
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(prepared),
  )
  let preimage = "{\"result_name\":\"out\",\"unit_definition_cid\":\"" +
    @checked.unit_definition_cid(program, 0).unwrap() +
    "\",\"version\":\"actql-local-result-definition/0.1\"}"
  assert_eq(
    client_effect_local_result_definition_cid(issued),
    "sha256:" + @sha.hex(@utf8.encode(preimage)),
  )
  assert_true(
    client_effect_local_result_definition_json(issued).contains(
      "\"self_cid\":\"" +
      client_effect_local_result_definition_cid(issued) +
      "\"",
    ),
  )
  assert_true(
    client_effect_local_result_definition_matches(issued, prepared, 0, "out"),
  )
  assert_true(
    !client_effect_local_result_definition_matches(issued, prepared, 1, "out"),
  )
  assert_true(
    !client_effect_local_result_definition_matches(issued, prepared, 0, "other"),
  )
  assert_true(
    issue_client_effect_local_result_definition(
      prepared, 0, "other", 4096, 16, 4,
    )
    is Err(MissingResult),
  )
  assert_true(
    issue_client_effect_local_result_definition(prepared, 1, "out", 4096, 16, 4)
    is Err(MissingUnit),
  )
  let foreign = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    !client_effect_local_result_definition_matches(issued, foreign, 0, "out"),
  )
  let run_bound = @publication.prepare_result_definition(
    prepared_client_effect_computation_definition_cid(prepared),
    "out",
  ).unwrap()
  assert_true(
    client_effect_local_result_definition_cid(issued) !=
    @publication.result_definition_cid(run_bound),
  )
}

///|
test "same Result name in another checked Unit has another local definition" {
  let (_, environment, limits) = client_effect_fixture()
  let document =
    #|{"version":"actql/0.1","id":"two-unit-effect","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}},{"id":"other","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":2}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let first = issue_client_effect_local_result_definition(
    prepared, 0, "out", 4096, 16, 4,
  ).unwrap()
  let second = issue_client_effect_local_result_definition(
    prepared, 1, "out", 4096, 16, 4,
  ).unwrap()
  assert_true(
    client_effect_local_result_definition_cid(first) !=
    client_effect_local_result_definition_cid(second),
  )
  assert_true(
    !client_effect_local_result_definition_matches(first, prepared, 1, "out"),
  )
  assert_true(
    client_effect_local_result_definition_matches(second, prepared, 1, "out"),
  )
}

///|
test "checked Effect member resolution retains the exact Stage and Mapping" {
  let (document, environment, limits) = client_effect_fixture()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let descriptor = client_effect_member_descriptor(prepared, 0, "save", 16).unwrap()
  assert_eq(descriptor.0, 0)
  assert_eq(descriptor.1, "save")
  assert_eq(descriptor.2, "create")
  assert_eq(descriptor.3, "connector://crm/account")
  assert_eq(descriptor.4, "mapping:crm.account.v1")
  assert_eq(descriptor.6, Some("out"))
  assert_true(
    client_effect_member_descriptor(prepared, 1, "save", 16)
    is Err(InvalidMember),
  )
  assert_true(
    client_effect_member_descriptor(prepared, 0, "foreign", 16)
    is Err(InvalidMember),
  )
  assert_true(
    client_effect_member_descriptor(prepared, 0, "save", 1) is Err(WorkLimit),
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
  let effect_scope = prepared_client_effect_request_scope(prepared, request).unwrap()
  assert_eq(
    @request_scope.logical_request_scope_cid(effect_scope),
    client_request_scope_cid(request),
  )
  assert_eq(effect_scope, client_request_logical_scope(replay))
  let restored = admit_client_request_identity_record(
    client_request_authority_scope_cid(request),
    client_request_caller_id(request),
    client_request_program_cid(request),
    client_request_parameters_cid(request),
    client_request_input_cid(request),
    client_request_scope_cid(request),
    client_request_intent_cid(request),
  ).unwrap()
  assert_eq(
    prepared_client_effect_request_scope(prepared, restored).unwrap(),
    effect_scope,
  )
  let other_program = prepare_client_effect_computation(
    document.replace(old="client-effect", new="another-effect"),
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    prepared_client_effect_request_scope(other_program, request)
    is Err(IdentityMismatch),
  )
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

///|
test "Effectful compiler issues owner-bound Plan and Template" {
  let (document, environment, limits) = client_effect_fixture()
  let owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let manifests = admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let sequence : @lower.SequenceLimits = {
    max_steps: 10,
    max_rows: 10,
    max_cells: 10,
    max_bindings: 10,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 10,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }
  let compiled = issue_prepared_client_effect_compilation(
    owner, manifests, sequence, 1000, 10000, 1000000, 100000, 100,
  ).unwrap()
  assert_true(physical_equal(client_effect_compilation_owner(compiled), owner))
  assert_true(
    client_effect_compilation_result_transformation(compiled, owner, 0)
    is Ok(None),
  )
  assert_true(
    client_effect_compilation_result_transformation(compiled, owner, -1)
    is Err(MismatchedCompilation),
  )
  assert_true(
    client_effect_compilation_result_transformation(compiled, owner, 1)
    is Err(MismatchedCompilation),
  )
  let plan = client_effect_compilation_plan(compiled)
  let wire = client_task_executable_plan_wire(plan)
  let facts = client_task_executable_plan_fact_manifest_wire(plan)
  let template = @publication.run_evidence_value_json(
    client_effect_compilation_template(compiled),
  )
  let envelope = @publication.publication_contract_json(
    client_effect_compilation_compiled_plan(compiled),
  )
  assert_true(wire.contains("\"effect_result\""))
  assert_true(wire.contains("\"effects\":{\"save\":"))
  assert_true(wire.contains("\"effect_plan_logical_cids\":{}"))
  assert_true(
    template.contains(prepared_client_effect_computation_definition_cid(owner)),
  )
  let policy = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let (observation, invocation) = issue_client_effect_source_free_invocation(
    compiled, policy, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      @publication.run_evidence_value_identity(
        client_effect_compilation_template(compiled),
      ),
    ),
  )
  assert_true(
    @publication.publication_contract_json(invocation).contains(
      @publication.run_evidence_value_identity(observation),
    ),
  )
  assert_true(
    issue_client_effect_source_free_invocation(compiled, "", 100000, 10000, 100)
    is Err(_),
  )
  assert_true(envelope.contains(client_task_executable_plan_cid(plan)))
  let restored = admit_prepared_client_effect_compilation(
    owner, wire, facts, template, envelope, manifests, sequence, 1000, 10000, 1000000,
    100000, 100,
  ).unwrap()
  assert_true(physical_equal(client_effect_compilation_owner(restored), owner))
  let changed = prepare_client_effect_computation(
    document.replace(old="\"save\":", new="\"other\":"),
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    admit_prepared_client_effect_compilation(
      changed, wire, facts, template, envelope, manifests, sequence, 1000, 10000,
      1000000, 100000, 100,
    )
    is Err(ClientEffectCompilationAdmissionIssue::MismatchedCompilation),
  )
  assert_true(
    admit_prepared_client_effect_compilation(
      owner, wire, facts, "{}", envelope, manifests, sequence, 1000, 10000, 1000000,
      100000, 100,
    )
    is Err(ClientEffectCompilationAdmissionIssue::MismatchedCompilation),
  )
  assert_true(
    issue_prepared_client_effect_compilation(
      owner, manifests, sequence, 1000, 10000, 1, 100000, 100,
    )
    is Err(_),
  )
  let allowed = issue_client_effect_allowed_run(
    compiled, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "namespace-a", "effect-run", "2026-09-26T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let bound = bind_client_effect_compiled_run(owner, allowed, definition).unwrap()
  assert_true(
    physical_equal(prepared_client_effect_run_computation(bound), owner),
  )
  assert_true(
    bind_client_effect_compiled_run(changed, allowed, definition)
    is Err(ClientEffectCompiledRunIssue::ForeignCompilation),
  )
  let equal_owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    bind_client_effect_compiled_run(equal_owner, allowed, definition)
    is Err(ClientEffectCompiledRunIssue::ForeignCompilation),
  )
  let restored_allowed = admit_client_effect_allowed_run(
    compiled,
    client_effect_allowed_run_prepared(allowed),
    client_effect_allowed_run_authorization(allowed),
  ).unwrap()
  assert_true(
    client_effect_compilation_result_transformation(compiled, equal_owner, 0)
    is Err(MismatchedCompilation),
  )
  ignore(
    bind_client_effect_compiled_run(owner, restored_allowed, definition).unwrap(),
  )
  let foreign_compilation = issue_prepared_client_effect_compilation(
    changed, manifests, sequence, 1000, 10000, 1000000, 100000, 100,
  ).unwrap()
  assert_true(
    admit_client_effect_allowed_run(
      foreign_compilation,
      client_effect_allowed_run_prepared(allowed),
      client_effect_allowed_run_authorization(allowed),
    )
    is Err(ClientEffectCompiledRunIssue::Admission(_)),
  )
}
