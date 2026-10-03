///|
test "ordinary values document prepares one named Effect-free result" {
  let environment = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"client-values","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
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
  let limits : ClientProgramPreparationLimits = {
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
  }
  let selected = @checked.checking_environment(
    environment,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let prepared = match
    prepare_effect_free_client_program(document, Json, selected, None, limits) {
    Ok(value) => value
    Err(_) => fail("ordinary values preparation failed")
  }
  assert_eq(prepared_client_result_count(prepared), 1)
  assert_eq(prepared_client_result_name(prepared, 0), Some("answer"))
  assert_eq(@strategy.graph_task_count(prepared_client_graph(prepared)), 1)
  let result_row = issue_prepared_client_result_row_contract(
    prepared, 0, 0, 10000, 1000, 20,
  ).unwrap()
  assert_eq(client_result_row_contract_name(result_row), "rows")
  assert_eq(
    client_result_row_contract_unit_cid(result_row),
    @checked.unit_definition_cid(
      @strategy.graph_program(prepared_client_graph(prepared)),
      0,
    ).unwrap(),
  )
  assert_eq(
    client_result_row_contract_wire(result_row),
    "{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
  )
  assert_eq(
    client_result_row_contract_cid(result_row),
    "sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c",
  )
  let result_plan = issue_prepared_client_result_plan(
    prepared, 0, 10000, 1000, 20,
  ).unwrap()
  assert_eq(client_result_plan_name(result_plan), "answer")
  assert_eq(
    client_result_plan_row_contract_cid(result_plan),
    client_result_row_contract_cid(result_row),
  )
  assert_eq(
    client_result_plan_wire(result_plan),
    (
      #|{"order":{"strategy":"inherited","terms":[]},"projection":[{"input":"id","output":"id","value_contract_cid":"sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d"}],"result_name":"answer","result_plan_logical_cid":"sha256:457f27fe1a1f226e1ebab73824370e2242c003886619e37e4f18ed866c897d3f","typed_output_port":{"carrier":"relation","name":"rows","row_contract_cid":"sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c"},"unit_definition_cid":"sha256:bd1d8948bb65f17b94e971ec556f43add62bec77e59fdb3723f588cfe7b76810","unit_result_name":"rows","unit_result_ordinal":0,"version":"actql-result-plan/0.1"}
    ),
  )
  assert_eq(
    client_result_plan_cid(result_plan),
    "sha256:457f27fe1a1f226e1ebab73824370e2242c003886619e37e4f18ed866c897d3f",
  )
  assert_eq(
    client_result_plan_cid(
      admit_prepared_client_result_plan(
        prepared,
        0,
        client_result_plan_wire(result_plan),
        10000,
        1000,
        20,
      ).unwrap(),
    ),
    client_result_plan_cid(result_plan),
  )
  assert_true(
    admit_prepared_client_result_plan(
      prepared,
      0,
      client_result_plan_wire(result_plan).replace(
        old="\"result_name\":\"answer\"",
        new="\"result_name\":\"foreign\"",
      ),
      10000,
      1000,
      20,
    )
    is Err(ClientResultPlanAdmissionIssue::MismatchedPlan),
  )
  assert_true(
    issue_prepared_client_result_plan(prepared, 1, 10000, 1000, 20)
    is Err(ClientResultPlanIssue::MissingResult),
  )
  assert_true(
    issue_prepared_client_result_row_contract(prepared, 0, 1, 10000, 1000, 20)
    is Err(ClientResultRowContractIssue::MissingPublication),
  )
  assert_true(
    issue_prepared_client_result_row_contract(prepared, 0, 0, 1, 1000, 20)
    is Err(ClientResultRowContractIssue::Encoding(_)),
  )
  assert_eq(
    @checked.unit_publication_count(
      @strategy.graph_program(prepared_client_graph(prepared)),
      0,
    ),
    Some(1),
  )
  let rows_limit = emit_prepared_client_publication_limit(
    prepared,
    0,
    0,
    Rows,
    10000,
    1000,
    20,
  ).unwrap()
  let bytes_limit = emit_prepared_client_publication_limit(
    prepared,
    0,
    0,
    Bytes,
    10000,
    1000,
    20,
  ).unwrap()
  assert_true(rows_limit != bytes_limit)
  let rows_binding = emit_prepared_client_publication_binding(
    prepared,
    0,
    0,
    Rows,
    10000,
    1000,
    20,
  ).unwrap()
  let bytes_binding = emit_prepared_client_publication_binding(
    prepared,
    0,
    0,
    Bytes,
    10000,
    1000,
    20,
  ).unwrap()
  assert_true(rows_binding != bytes_binding)
  let facts = issue_prepared_client_publication_plan_facts(
    prepared, 2, 10000, 1000, 20,
  ).unwrap()
  assert_eq(client_publication_plan_fact_limits(facts), [
    rows_limit, bytes_limit,
  ])
  assert_eq(client_publication_plan_fact_bindings(facts), [
    rows_binding, bytes_binding,
  ])
  let rows_entry = "{\"kind\":\"resolved_limit\",\"value\":" + rows_limit + "}"
  let bytes_entry = "{\"kind\":\"resolved_limit\",\"value\":" +
    bytes_limit +
    "}"
  assert_eq(client_publication_plan_fact_entries(facts), [
    rows_entry, bytes_entry,
  ])
  let witnesses = issue_prepared_client_publication_witnesses(
    prepared, 10, 10000, 1000, 20,
  ).unwrap()
  let witness_bodies = client_publication_witness_bodies(witnesses)
  let witness_cids = client_publication_witness_cids(witnesses)
  assert_eq(witness_bodies.length(), 3)
  assert_eq(witness_cids.length(), 3)
  assert_true(witness_cids[0] != witness_cids[1])
  assert_true(
    admit_prepared_client_publication_witnesses(
      prepared, witness_bodies, 10, 10000, 1000, 20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_publication_witnesses(
      prepared,
      [witness_bodies[0]],
      10,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationWitnessAdmissionIssue::MismatchedWitnesses),
  )
  assert_true(
    admit_prepared_client_publication_witnesses(
      prepared,
      [witness_bodies[1], witness_bodies[0], witness_bodies[2]],
      10,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationWitnessAdmissionIssue::MismatchedWitnesses),
  )
  assert_true(
    issue_prepared_client_publication_witnesses(prepared, 2, 10000, 1000, 20)
    is Err(ClientPublicationWitnessIssue::BudgetExceeded),
  )
  assert_true(
    admit_prepared_client_publication_fact_entries(
      prepared,
      [bytes_entry, rows_entry],
      2,
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_publication_fact_entries(
      prepared,
      [rows_entry],
      2,
      10000,
      1000,
      20,
    )
    is Err(MissingEntry),
  )
  assert_true(
    admit_prepared_client_publication_fact_entries(
      prepared,
      [rows_entry, rows_entry],
      2,
      10000,
      1000,
      20,
    )
    is Err(DuplicateEntry),
  )
  assert_true(
    admit_prepared_client_publication_fact_entries(
      prepared,
      [rows_entry, "{\"kind\":\"contract_fact\",\"value\":" + bytes_limit + "}"],
      2,
      10000,
      1000,
      20,
    )
    is Err(UnexpectedEntry),
  )
  assert_true(
    admit_prepared_client_publication_fact_entries(
      prepared,
      ["x".repeat(10001), bytes_entry],
      2,
      10000,
      1000,
      20,
    )
    is Err(BudgetExceeded),
  )
  let changed_limits = client_publication_plan_fact_limits(facts)
  changed_limits.push("foreign")
  assert_eq(client_publication_plan_fact_limits(facts).length(), 2)
  let changed_entries = client_publication_plan_fact_entries(facts)
  changed_entries.push("foreign")
  assert_eq(client_publication_plan_fact_entries(facts).length(), 2)
  assert_true(
    issue_prepared_client_publication_plan_facts(prepared, 1, 10000, 1000, 20)
    is Err(ClientPublicationPlanFactIssue::Limits(BudgetExceeded)),
  )
  assert_true(
    admit_prepared_client_publication_plan_facts(
      prepared,
      [bytes_limit, rows_limit],
      [bytes_binding, rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_publication_plan_facts(
      prepared,
      [rows_limit],
      [bytes_binding, rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationPlanFactIssue::Limits(MissingLimit)),
  )
  assert_true(
    admit_prepared_client_publication_plan_facts(
      prepared,
      [rows_limit, rows_limit],
      [bytes_binding, rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationPlanFactIssue::Limits(DuplicateLimit)),
  )
  assert_true(
    admit_prepared_client_publication_plan_facts(
      prepared,
      [rows_limit, bytes_limit],
      [rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationPlanFactIssue::Bindings(MissingBinding)),
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [bytes_binding, rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingSetIssue::MissingBinding),
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [rows_binding, rows_binding],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingSetIssue::DuplicateBinding),
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [bytes_binding, "{}"],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingSetIssue::InvalidBinding),
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [bytes_binding, rows_binding],
      1,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingSetIssue::BudgetExceeded),
  )
  assert_true(
    admit_prepared_client_publication_binding(
      prepared,
      0,
      0,
      Rows,
      rows_binding,
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_publication_binding(
      prepared,
      0,
      0,
      Bytes,
      rows_binding,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingAdmissionIssue::MismatchedBinding),
  )
  let wrong_port = rows_binding.replace(
    old="\"result_name\":\"rows\"",
    new="\"result_name\":\"answer\"",
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [bytes_binding, wrong_port],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingSetIssue::MismatchedBinding),
  )
  let foreign_cid = rows_binding.replace(
    old="\"binding_cid\":\"sha256:",
    new="\"binding_cid\":\"sha256:f",
  )
  assert_true(
    admit_prepared_client_publication_binding_set(
      prepared,
      [bytes_binding, foreign_cid],
      2,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingSetIssue::UnexpectedBinding),
  )
  assert_true(
    admit_prepared_client_publication_binding(
      prepared,
      0,
      0,
      Rows,
      wrong_port,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingAdmissionIssue::MismatchedBinding),
  )
  assert_true(
    emit_prepared_client_publication_binding(
      prepared,
      0,
      1,
      Rows,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationBindingIssue::MissingPublication),
  )
  assert_true(
    emit_prepared_client_publication_binding(
      prepared,
      0,
      0,
      Rows,
      rows_binding.length() - 1,
      1000,
      20,
    )
    is Err(ClientPublicationBindingIssue::Encoding),
  )
  assert_true(
    emit_prepared_client_publication_limit(
      prepared,
      0,
      1,
      Rows,
      10000,
      1000,
      20,
    )
    is Err(ClientPublicationLimitIssue::MissingPublication),
  )
  assert_true(
    emit_prepared_client_publication_limit(
      prepared,
      0,
      0,
      Rows,
      rows_limit.length() - 1,
      1000,
      20,
    )
    is Err(ClientPublicationLimitIssue::Encoding),
  )
  let identity = prepared_client_identity(prepared)
  assert_eq(
    prepared_client_check_environment_cid(prepared),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
  )
  let semantics_cid = prepared_client_program_semantics_cid(prepared)
  assert_true(semantics_cid.has_prefix("sha256:"))
  assert_eq(semantics_cid.length(), 71)
  let definition = emit_prepared_client_program_definition(
    prepared, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    definition,
    "{\"id\":\"client-values\",\"program_semantics_cid\":\"" +
    semantics_cid +
    "\",\"version\":\"actql-program-definition/0.1\"}",
  )
  let semantic_program = emit_prepared_client_semantic_program(
    prepared, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    semantic_program, "{\"id\":\"client-values\",\"results\":{\"answer\":{\"from\":{\"result\":\"rows\",\"stage\":\"source\"}}},\"stages\":[{\"id\":\"source\",\"inputs\":{},\"results\":{\"rows\":{\"fields\":[\"id\"],\"from\":\"selected\"}},\"steps\":[{\"as\":\"selected\",\"values\":{\"rows\":[{\"id\":1},{\"id\":2}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}]}],\"version\":\"actql/0.1\"}",
  )
  assert_true(
    emit_prepared_client_semantic_program(
      prepared,
      semantic_program.length() - 1,
      1000,
      20,
    )
    is Err(ClientIdentityMaterialIssue::Encoding),
  )
  let semantics = emit_prepared_client_program_semantics(
    prepared, 10000, 1000, 20,
  ).unwrap()
  assert_eq("sha256:" + @sha.hex(@utf8.encode(semantics)), semantics_cid)
  let stage_semantics = emit_prepared_client_stage_semantics(
    prepared, 0, 10000, 1000, 20,
  ).unwrap()
  let source = @checked.source_identity(
    @strategy.graph_program(prepared_client_graph(prepared)),
  )
  let expected_stage_cid = @program_refs.program_semantics_stage_cid(
    @program_refs.program_definition_semantics(
      @context.program_identity_definition(source),
    ),
    0,
  ).unwrap()
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(stage_semantics)),
    expected_stage_cid,
  )
  assert_true(
    emit_prepared_client_stage_semantics(prepared, 1, 10000, 1000, 20)
    is Err(ClientIdentityMaterialIssue::MissingStage),
  )
  assert_true(
    emit_prepared_client_program_semantics(
      prepared,
      semantics.length() - 1,
      1000,
      20,
    )
    is Err(ClientIdentityMaterialIssue::Encoding),
  )
  assert_true(
    emit_prepared_client_program_definition(
      prepared,
      definition.length() - 1,
      1000,
      20,
    )
    is Err(ClientIdentityMaterialIssue::Encoding),
  )
  assert_eq(
    identity.program_definition_cid,
    "sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c",
  )
  assert_eq(
    identity.parameter_values_cid,
    "sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52",
  )
  let aoa_limits : @lower.SequenceLimits = {
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
  let steps = emit_prepared_client_task_aoa_steps(
    prepared, 0, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    steps, "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1},{\"id\":2}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}]",
  )
  let pipeline = emit_prepared_client_values_pipeline(
    prepared, 0, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    pipeline, "{\"output\":\"values_0\",\"sources\":{},\"steps\":[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1},{\"id\":2}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  assert_eq(
    emit_prepared_client_task_pipeline(prepared, 0, aoa_limits, 10000, 1000, 20).unwrap(),
    pipeline,
  )
  let aoa = issue_prepared_client_values_aoa_identity(
    prepared, 0, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  assert_eq(client_values_aoa_identity_wire(aoa), pipeline)
  // Independently hashed from the specified one-step AoA body.
  assert_eq(
    client_values_aoa_identity_cid(aoa),
    "sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723",
  )
  assert_eq(
    emit_prepared_client_values_unit_source(
      prepared, 0, aoa_limits, 10000, 1000, 20,
    ).unwrap(),
    "{\"id\":\"source\",\"inputs\":{},\"results\":{\"rows\":{\"fields\":[\"id\"],\"from\":\"selected\"}},\"steps\":[{\"as\":\"selected\",\"values\":{\"rows\":[{\"id\":1},{\"id\":2}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}],\"version\":\"actql/0.1\"}",
  )
  assert_true(
    emit_prepared_client_values_unit_source(
      prepared, 1, aoa_limits, 10000, 1000, 20,
    )
    is Err(UnsupportedSource),
  )
  let schema_limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: 10,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let output_schema = issue_prepared_client_values_output_schema(
    prepared, 0, aoa_limits, schema_limits, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    @execution.relation_schema_wire(output_schema),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_eq(
    @execution.relation_schema_cid(output_schema),
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  let fragment = issue_prepared_client_values_fragment(
    prepared, 0, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  assert_eq(client_values_fragment_node_id(fragment), "values_0")
  assert_eq(
    client_values_fragment_logical_cid(fragment),
    "sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723",
  )
  assert_eq(
    client_values_fragment_output_contract_wire(fragment),
    "{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
  )
  assert_eq(
    client_values_fragment_output_contract_cid(fragment),
    "sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c",
  )
  assert_eq(
    client_values_fragment_wire(fragment),
    "{\"input_contracts\":{},\"kind\":\"aoa_fragment\",\"logical_cid\":\"sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723\",\"node_id\":\"values_0\",\"output_contracts\":{\"values_0\":\"sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c\"},\"pipeline\":" +
    pipeline +
    "}",
  )
  let root = issue_prepared_client_direct_values_result_root(
    prepared, 0, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  let root_wire = "{\"name\":\"answer\",\"ref\":{\"node_id\":\"values_0\",\"port\":\"values_0\"},\"role\":\"requested_result\"}"
  assert_eq(client_direct_result_root_wire(root), root_wire)
  let graph_component = issue_prepared_client_values_plan_graph(
    prepared, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  let compiler_manifests = admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let template = issue_prepared_source_free_client_bound_template(
    prepared, compiler_manifests, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  assert_true(
    @publication.run_evidence_value_json(template).contains(
      "\"grammar_manifest_cid\":\"" +
      @environment.compiler_grammar_manifest_cid() +
      "\"",
    ),
  )
  assert_true(
    @publication.run_evidence_value_json(template).contains(
      "\"barrier_contract_manifest_cid\":\"" +
      @environment.compiler_barrier_contract_manifest_cid() +
      "\"",
    ),
  )
  let material = issue_prepared_client_values_execution_material(
    prepared, compiler_manifests, aoa_limits, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    client_execution_material_template_cid(material),
    @publication.run_evidence_value_identity(template),
  )
  let material_wire = client_execution_material_wire(material)
  assert_true(
    material_wire.contains(
      "\"aoa_contract_cid\":\"" +
      @environment.compiler_aoa_contract_cid() +
      "\"",
    ),
  )
  assert_true(
    material_wire.contains(
      "\"result_plan_logical_cids\":{\"answer\":\"" +
      client_result_plan_cid(result_plan) +
      "\"}",
    ),
  )
  assert_true(material_wire.contains("\"effect_plan_logical_cids\":{}"))
  assert_true(material_wire.contains("\"parameter_names\":[]"))
  assert_eq(
    client_execution_material_wire(
      admit_prepared_client_values_execution_material(
        prepared, material_wire, compiler_manifests, aoa_limits, 10000, 1000, 20,
      ).unwrap(),
    ),
    material_wire,
  )
  assert_true(
    admit_prepared_client_values_execution_material(
      prepared,
      material_wire.replace(
        old=client_result_plan_cid(result_plan),
        new=@environment.compiler_grammar_manifest_cid(),
      ),
      compiler_manifests,
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Err(ClientExecutionMaterialAdmissionIssue::MismatchedMaterial),
  )
  let executable = issue_prepared_client_values_executable_plan(
    prepared, compiler_manifests, aoa_limits, 32, 64, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    client_values_executable_plan_cid(executable).has_prefix("sha256:"),
  )
  let executable_wire = client_values_executable_plan_wire(executable)
  let manifest_wire = client_values_executable_plan_fact_manifest_wire(
    executable,
  )
  assert_true(
    executable_wire.contains(
      "\"plan_fact_manifest_cid\":\"" +
      client_values_executable_plan_fact_manifest_cid(executable) +
      "\"",
    ),
  )
  assert_true(executable_wire.contains(material_wire))
  assert_eq(
    client_values_executable_plan_cid(
      admit_prepared_client_values_executable_plan(
        prepared, executable_wire, manifest_wire, compiler_manifests, aoa_limits,
        32, 64, 100000, 10000, 100,
      ).unwrap(),
    ),
    client_values_executable_plan_cid(executable),
  )
  assert_true(
    admit_prepared_client_values_executable_plan(
      prepared,
      executable_wire.replace(old="\"answer\"", new="\"foreign\""),
      manifest_wire,
      compiler_manifests,
      aoa_limits,
      32,
      64,
      100000,
      10000,
      100,
    )
    is Err(ClientValuesExecutablePlanAdmissionIssue::MismatchedPlan),
  )
  let compilation = issue_prepared_client_values_compilation(
    prepared, compiler_manifests, aoa_limits, 32, 64, 100000, 10000, 100,
  ).unwrap()
  // Equal content does not make a separately prepared owner interchangeable.
  let foreign_prepared = prepare_effect_free_client_program(
    document,
    Json,
    selected,
    None,
    limits,
  ).unwrap()
  let policy_cid = "sha256:" + "1".repeat(64)
  let allowed = issue_client_values_compiled_run(
    prepared, compilation, policy_cid, policy_cid, "2027-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(client_compiled_run_matches(allowed, prepared))
  assert_false(client_compiled_run_matches(allowed, foreign_prepared))
  assert_true(
    issue_client_values_compiled_run(
      foreign_prepared, compilation, policy_cid, policy_cid, "2027-01-01T00:00:00.000Z",
    )
    is Err(ClientCompiledRunIssue::ForeignOwner),
  )
  let run_definition = issue_client_compiled_run_definition(
    allowed, "local", "values-owner-run", "2026-09-27T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    bind_source_free_client_values_run(
      foreign_prepared,
      compilation,
      client_compiled_run_admission(allowed),
      run_definition,
    )
    is Err(ClientValuesRunBindingIssue::ForeignRun),
  )
  let restored = admit_client_compiled_run_definition(
    allowed,
    @publication.publication_contract_json(run_definition),
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(restored),
    @publication.publication_contract_identity(run_definition),
  )
  let task_compilation = issue_prepared_client_task_compilation(
    prepared, compiler_manifests, aoa_limits, 32, 64, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    issue_client_task_compiled_run(
      foreign_prepared, task_compilation, policy_cid, policy_cid, "2027-01-01T00:00:00.000Z",
    )
    is Err(ClientCompiledRunIssue::ForeignOwner),
  )
  let task_allowed = issue_client_task_compiled_run(
    prepared, task_compilation, policy_cid, policy_cid, "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let task_definition = issue_client_compiled_run_definition(
    task_allowed, "local", "tasks-owner-run", "2026-09-27T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    bind_client_task_run(
      foreign_prepared,
      task_compilation,
      client_compiled_run_admission(task_allowed),
      task_definition,
    )
    is Err(ClientTaskRunBindingIssue::ForeignRun),
  )
  let compiled_wire = @publication.publication_contract_json(
    client_values_compilation_compiled_plan(compilation),
  )
  assert_true(
    compiled_wire.contains(
      "\"executable_plan_cid\":\"" +
      client_values_executable_plan_cid(executable) +
      "\"",
    ),
  )
  assert_true(
    compiled_wire.contains("\"compiler_version\":\"actql-moonbit-0.0.1\""),
  )
  assert_true(compiled_wire.contains("\"aoa_ir_version\":\"aoa-pipeline:0.1\""))
  assert_eq(
    @publication.publication_contract_json(
      client_values_compilation_compiled_plan(
        admit_prepared_client_values_compilation(
          prepared,
          executable_wire,
          manifest_wire,
          @publication.run_evidence_value_json(
            client_values_compilation_template(compilation),
          ),
          compiled_wire,
          compiler_manifests,
          aoa_limits,
          32,
          64,
          100000,
          10000,
          100,
        ).unwrap(),
      ),
    ),
    compiled_wire,
  )
  assert_eq(
    client_values_plan_graph_wire(graph_component),
    "{\"data_edges\":[],\"nodes\":[" +
    client_values_fragment_wire(fragment) +
    "],\"root_refs\":[" +
    root_wire +
    "]}",
  )
  assert_eq(
    client_values_plan_graph_wire(
      admit_prepared_client_values_plan_graph(
        prepared,
        client_values_plan_graph_wire(graph_component),
        aoa_limits,
        10000,
        1000,
        20,
      ).unwrap(),
    ),
    client_values_plan_graph_wire(graph_component),
  )
  assert_true(
    admit_prepared_client_values_plan_graph(
      prepared,
      client_values_plan_graph_wire(graph_component).replace(
        old="\"answer\"",
        new="\"foreign\"",
      ),
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Err(ClientValuesPlanGraphAdmissionIssue::MismatchedGraph),
  )
  assert_true(
    issue_prepared_client_values_plan_graph(prepared, aoa_limits, 0, 1000, 20)
    is Err(ClientValuesPlanGraphIssue::InvalidLimits),
  )
  assert_eq(client_direct_result_root_name(root), "answer")
  assert_eq(
    client_direct_result_root_plan_cid(root),
    client_result_plan_cid(result_plan),
  )
  assert_eq(
    client_direct_result_root_row_contract_cid(root),
    client_values_fragment_output_contract_cid(fragment),
  )
  assert_eq(
    client_direct_result_root_wire(
      admit_prepared_client_direct_values_result_root(
        prepared, 0, root_wire, aoa_limits, 10000, 1000, 20,
      ).unwrap(),
    ),
    root_wire,
  )
  assert_true(
    admit_prepared_client_direct_values_result_root(
      prepared,
      0,
      root_wire.replace(old="\"answer\"", new="\"foreign\""),
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Err(ClientDirectResultRootAdmissionIssue::MismatchedRoot),
  )
  assert_true(
    issue_prepared_client_direct_values_result_root(
      prepared, 1, aoa_limits, 10000, 1000, 20,
    )
    is Err(ClientDirectResultRootIssue::MissingResult),
  )
  assert_eq(
    client_values_fragment_wire(
      admit_prepared_client_values_fragment(
        prepared,
        0,
        client_values_fragment_wire(fragment),
        aoa_limits,
        10000,
        1000,
        20,
      ).unwrap(),
    ),
    client_values_fragment_wire(fragment),
  )
  assert_true(
    admit_prepared_client_values_fragment(
      prepared,
      0,
      client_values_fragment_wire(fragment).replace(
        old="\"values_0\"",
        new="\"values_1\"",
      ),
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Err(ClientValuesFragmentAdmissionIssue::MismatchedNode),
  )
  assert_true(
    issue_prepared_client_values_fragment(
      prepared, 1, aoa_limits, 10000, 1000, 20,
    )
    is Err(ClientValuesFragmentIssue::AoA(_)),
  )
  assert_true(
    issue_prepared_client_values_fragment(prepared, 0, aoa_limits, 1, 1000, 20)
    is Err(ClientValuesFragmentIssue::AoA(_)),
  )
  assert_true(
    issue_prepared_client_values_output_schema(
      prepared,
      0,
      aoa_limits,
      { ..schema_limits, max_fields: 0, },
      10000,
      1000,
      20,
    )
    is Err(Identity(@execution.RelationSchemaIdentityIssue::FieldLimit)),
  )
  assert_true(
    admit_prepared_client_values_aoa_identity(
      prepared,
      0,
      pipeline,
      client_values_aoa_identity_cid(aoa),
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_values_aoa_identity(
      prepared,
      0,
      pipeline.replace(
        old="{\"output\":\"values_0\",\"sources\":{}",
        new="{\"sources\":{},\"output\":\"values_0\"",
      ),
      client_values_aoa_identity_cid(aoa),
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
  assert_true(
    admit_prepared_client_values_aoa_identity(
      prepared,
      0,
      pipeline.replace(old="\"id\":2", new="\"id\":3"),
      client_values_aoa_identity_cid(aoa),
      aoa_limits,
      10000,
      1000,
      20,
    )
    is Err(PipelineMismatch),
  )
  assert_true(
    admit_prepared_client_values_aoa_identity(
      prepared, 0, pipeline, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      aoa_limits, 10000, 1000, 20,
    )
    is Err(CidMismatch),
  )
  assert_true(
    issue_prepared_client_values_aoa_identity(
      prepared, 1, aoa_limits, 10000, 1000, 20,
    )
    is Err(
      ClientValuesAoAIdentityIssue::Pipeline(
        ClientValuesPipelineIssue::MissingTask
      )
    ),
  )
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared, 1, aoa_limits, 10000, 1000, 20,
    )
    is Err(ClientValuesPipelineIssue::MissingTask),
  )
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared,
      0,
      aoa_limits,
      pipeline.length() - 1,
      1000,
      20,
    )
    is Err(ClientValuesPipelineIssue::Encoding),
  )
  assert_true(
    emit_prepared_client_task_aoa_steps(
      prepared, 1, aoa_limits, 10000, 1000, 20,
    )
    is Err(MissingTask),
  )
  assert_true(
    emit_prepared_client_task_aoa_steps(
      prepared,
      0,
      aoa_limits,
      steps.length() - 1,
      1000,
      20,
    )
    is Err(Encoding),
  )
  assert_true(
    emit_prepared_client_task_aoa_steps(
      prepared,
      0,
      { ..aoa_limits, max_rows: 0, },
      10000,
      1000,
      20,
    )
    is Err(Sequence(_)),
  )
  assert_eq(
    identity.program_definition_cid,
    @strategy.graph_program_definition_cid(prepared_client_graph(prepared)),
  )
  let spaced = prepare_effect_free_client_program(
    " \n" + document + " \n",
    Json,
    selected,
    None,
    limits,
  ).unwrap()
  assert_eq(prepared_client_identity(spaced), identity)
  assert_eq(
    prepared_client_check_environment_cid(spaced),
    prepared_client_check_environment_cid(prepared),
  )
  assert_eq(prepared_client_program_semantics_cid(spaced), semantics_cid)
  assert_eq(
    emit_prepared_client_publication_limit(spaced, 0, 0, Rows, 10000, 1000, 20).unwrap(),
    rows_limit,
  )
  assert_eq(
    emit_prepared_client_program_definition(spaced, 10000, 1000, 20).unwrap(),
    definition,
  )
  assert_eq(
    emit_prepared_client_semantic_program(spaced, 10000, 1000, 20).unwrap(),
    semantic_program,
  )
  assert_eq(
    emit_prepared_client_program_semantics(spaced, 10000, 1000, 20).unwrap(),
    semantics,
  )
  assert_eq(
    emit_prepared_client_stage_semantics(spaced, 0, 10000, 1000, 20).unwrap(),
    stage_semantics,
  )
  assert_eq(
    emit_prepared_client_task_aoa_steps(spaced, 0, aoa_limits, 10000, 1000, 20).unwrap(),
    steps,
  )
  let changed = prepare_effect_free_client_program(
    document.replace(old="\"id\":2", new="\"id\":3"),
    Json,
    selected,
    None,
    limits,
  ).unwrap()
  assert_true(
    prepared_client_identity(changed).program_definition_cid !=
    identity.program_definition_cid,
  )
  assert_true(prepared_client_program_semantics_cid(changed) != semantics_cid)
  assert_true(
    emit_prepared_client_program_definition(changed, 10000, 1000, 20).unwrap() !=
    definition,
  )
  assert_true(
    emit_prepared_client_task_aoa_steps(changed, 0, aoa_limits, 10000, 1000, 20).unwrap() !=
    steps,
  )
  assert_eq(
    prepared_client_identity(changed).parameter_values_cid,
    identity.parameter_values_cid,
  )
  let scope_cid = "sha256:" + "a".repeat(64)
  let input_cid = "sha256:" + "b".repeat(64)
  assert_eq(
    source_free_caller_input_intent_cid(),
    "sha256:6ae68bff5e3ede5f6636cec5d87431d3a84b2c2b11af0698dd555a27e4c59d1f",
  )
  let source_free = prepare_source_free_client_request_identity(
    prepared, scope_cid, "no-input-request",
  ).unwrap()
  let source_free_identity = prepared_client_identity(prepared)
  assert_eq(
    admit_source_free_client_request_identity_record(
      scope_cid,
      "no-input-request",
      source_free_identity.program_definition_cid,
      source_free_identity.parameter_values_cid,
      source_free_caller_input_intent_cid(),
      client_request_scope_cid(source_free),
      client_request_intent_cid(source_free),
    ).unwrap(),
    source_free,
  )
  assert_true(
    admit_source_free_client_request_identity_record(
      scope_cid,
      "no-input-request",
      source_free_identity.program_definition_cid,
      source_free_identity.parameter_values_cid,
      input_cid,
      client_request_scope_cid(source_free),
      client_request_intent_cid(source_free),
    )
    is Err(InvalidInputIntent),
  )
  let request = prepare_client_request_identity(
    prepared, scope_cid, "saved-request", input_cid,
  ).unwrap()
  assert_eq(
    client_request_scope_cid(request),
    "sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3",
  )
  assert_eq(
    client_request_intent_cid(request),
    "sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d",
  )
  let readmitted = admit_client_request_identity_record(
    scope_cid,
    "saved-request",
    identity.program_definition_cid,
    identity.parameter_values_cid,
    input_cid,
    client_request_scope_cid(request),
    client_request_intent_cid(request),
  ).unwrap()
  assert_eq(readmitted, request)
  assert_eq(client_request_identity_relation(request, readmitted), SameRequest)
  assert_true(
    admit_client_request_identity_record(
      scope_cid,
      "saved-request",
      identity.program_definition_cid,
      identity.parameter_values_cid,
      input_cid,
      client_request_scope_cid(request),
      "sha256:" + "f".repeat(64),
    )
    is Err(IdentityMismatch),
  )
  assert_eq(
    prepare_client_request_identity(
      spaced, scope_cid, "saved-request", input_cid,
    ).unwrap(),
    request,
  )
  let changed_request = prepare_client_request_identity(
    changed, scope_cid, "saved-request", input_cid,
  ).unwrap()
  assert_eq(
    client_request_scope_cid(changed_request),
    client_request_scope_cid(request),
  )
  assert_true(
    client_request_intent_cid(changed_request) !=
    client_request_intent_cid(request),
  )
  assert_eq(
    client_request_identity_relation(changed_request, request),
    ChangedIntent,
  )
  let other_id = prepare_client_request_identity(
    prepared, scope_cid, "another-request", input_cid,
  ).unwrap()
  assert_true(
    client_request_scope_cid(other_id) != client_request_scope_cid(request),
  )
  assert_eq(
    client_request_intent_cid(other_id),
    client_request_intent_cid(request),
  )
  assert_eq(
    client_request_identity_relation(other_id, request),
    DifferentRequest,
  )
  let other_input = prepare_client_request_identity(
    prepared,
    scope_cid,
    "saved-request",
    "sha256:" + "c".repeat(64),
  ).unwrap()
  assert_eq(
    client_request_scope_cid(other_input),
    client_request_scope_cid(request),
  )
  assert_true(
    client_request_intent_cid(other_input) != client_request_intent_cid(request),
  )
  assert_true(
    prepare_client_request_identity(prepared, scope_cid, "", input_cid)
    is Err(InvalidRequestId),
  )
  assert_true(
    prepare_client_request_identity(
      prepared, "sha256:bad", "saved-request", input_cid,
    )
    is Err(InvalidAuthorityScope),
  )
  let run = open_prepared_source_free_client_run(prepared, {
    planning_work: 10000,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 10000L,
    retained_bytes: 10000L,
    execution_bytes: 10000L,
  }).unwrap()
  assert_true(
    open_prepared_source_free_client_run(prepared, {
      planning_work: -1,
      attempts: 2,
      holdings: 2,
      transfer_bytes: 10000L,
      retained_bytes: 10000L,
      execution_bytes: 10000L,
    })
    is Err(Ledger(_)),
  )
  assert_eq(@strategy.captured_compute_first_task(run), 0)
  assert_eq(@strategy.next_captured_task(run), Some(0))
  assert_false(@strategy.captured_task_completed(run, 0))
  assert_true(@strategy.captured_task_target(run, 0) is Some(_))
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 1,
    max_strategies: 1,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offer = @strategy.prepare_task_offer(
    run,
    0,
    @connector.capability_registration_at(registry, 0).unwrap(),
    1,
    [{ work_slots: [0], milliseconds: Some(1L), }],
    { transfer_bytes: 0L, retained_bytes: 10L, execution_bytes: 1L, },
    100,
  ).unwrap()
  guard @strategy.revise_strategy(run, [offer], registry, None)
    is Ok(Selected(revision)) else {
    fail("source-free root was not selected")
  }
  let request = @host_driver.prepare_dispatch_inputs(
    @host_driver.open_dispatch_driver(run),
    0,
    revision,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    100,
    10000,
  ).unwrap()
  assert_eq(@connector.fixed_compute_request_input_count(request), 0)
  assert_true(@connector.fixed_compute_request_inputs(request).is_empty())
  assert_true(@connector.fixed_compute_request_input(request, 0) is None)
  assert_true(
    prepare_effect_free_client_program(
      document.replace(old="actql/0.1", new="actql/9.9"),
      Json,
      selected,
      None,
      limits,
    )
    is Err(Syntax(_)),
  )
  assert_true(
    prepare_effect_free_client_program(document, Json, selected, None, {
      ..limits,
      lowering: { ..limits.lowering, max_nodes: 0, },
    })
    is Err(Lowering(_)),
  )
  let parameterized =
    #|{"version":"actql/0.1","id":"client-parameter","params":{"n":{"type":"number"}},"stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"value":"id + $n"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  guard prepare_effect_free_client_program(
      parameterized,
      Json,
      selected,
      None,
      limits,
    )
    is Err(NeedsInputs(requests)) else {
    fail("missing Parameter request was discarded")
  }
  assert_eq(@checked.input_request_count(requests), 1)
  let supplied = @decode.admit(
    @source.parse_json("{\"n\":\"bad\"}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 10,
      max_depth: 10,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    },
  ).unwrap()
  guard prepare_effect_free_client_program(
      parameterized,
      Json,
      selected,
      Some(supplied),
      limits,
    )
    is Err(Check(diagnostic)) else {
    fail("supplied Parameter diagnostic was discarded")
  }
  assert_eq(@checked.diagnostic_origin(diagnostic), Some(SuppliedValues))
  let bound_values = document
    .replace(
      old="\"id\":\"client-values\"",
      new="\"id\":\"client-bound-values\",\"params\":{\"n\":{\"type\":\"number\"}}",
    )
    .replace(old="\"id\":2", new="\"id\":{\"$param\":\"n\"}")
  for
    (supplied_body, expected_steps) in [
      ("{\"n\":2}", steps),
      ("{\"n\":3}", steps.replace(old="{\"id\":2}", new="{\"id\":3}")),
    ] {
    let supplied = @decode.admit(
      @source.parse_json(supplied_body, {
        max_input_bytes: 100,
        max_nodes: 10,
        max_depth: 10,
      }).unwrap(),
      {
        max_nodes: 10,
        max_depth: 10,
        max_string_bytes: 100,
        max_total_string_bytes: 100,
      },
    ).unwrap()
    let bound = prepare_effect_free_client_program(
      bound_values,
      Json,
      selected,
      Some(supplied),
      limits,
    ).unwrap()
    assert_eq(
      emit_prepared_client_task_aoa_steps(bound, 0, aoa_limits, 10000, 1000, 20).unwrap(),
      expected_steps,
    )
  }
}
