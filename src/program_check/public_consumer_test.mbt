///|
// Public test-package setup: no private constructor or reissued checked handle.
fn public_program_fixture() -> @program_check.CheckedProgram raise {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"public-reader","params":{"n":{"type":"number","default":1}},"stages":[{"id":"producer","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}},{"id":"consumer","inputs":{"rows":{"result":{"stage":"producer","result":"out"}}},"steps":[{"take":1,"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}}}],"results":{"out":{"from":{"stage":"consumer","result":"out"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 2,
    },
    format=Json,
  ).unwrap()
  // Input envelope CID independently calculated from canonical JSON with Node SHA-256.
  // It is not an expected Program identity computed by the product under test.
  let environment = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  // Scalar derive and take need no supplied capacity proofs. The consumer
  // closure has its own visit followed by its one imported producer visit.
  let material : @context.CapacityMaterial = { sources, consumers: [], }
  @program_check.check(
    program,
    environment,
    None,
    [[material], [material, material]],
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    public_source_limits(2),
    max_work=10000000,
    max_bytes=1000000,
    max_nodes=100000,
    max_depth=100,
  )
}

///|
test "external consumer reads formal Program decisions without private construction" {
  let program = public_program_fixture()
  assert_eq(@program_check.unit_count(program), 2)
  let identity = @program_check.source_identity(program)
  assert_eq(@context.program_identity_stage_count(identity), 2)
  let stage_values = @context.stage_identity_parameter_values(
    @context.program_identity_stage_at(identity, 0).unwrap(),
  )
  assert_eq(@parameter_refs.used_value_count(stage_values), 1)
  let parameter = @parameter_refs.used_value_at(stage_values, 0).unwrap()
  assert_eq(parameter.name, "n")
  assert_true(parameter.value.value is Number(1.0))
  assert_true(@parameter_refs.used_value_at(stage_values, 1) is None)
  let producer_cid = @program_check.unit_definition_cid(program, 0).unwrap()
  assert_true(
    producer_cid != @program_check.unit_definition_cid(program, 1).unwrap(),
  )
  let imported = @program_check.unit_result_import_at(program, 1, 0).unwrap()
  assert_eq(imported.input_name, "rows")
  assert_eq(imported.producer_program_id, "public-reader")
  assert_eq(imported.producer_node_id, "producer")
  assert_eq(imported.result_name, "out")
  assert_eq(imported.producer_unit_definition_cid, producer_cid)
  assert_eq(
    @program_check.unit_import_cid_at(program, 1, 0),
    Some(imported.cid),
  )
  assert_true(@program_check.unit_result_import_at(program, 1, 1) is None)
  let requirements = @program_check.requirements(program)
  let inputs = @context.stage_requirement_inputs(requirements)
  assert_eq(@context.local_input_closure_count(inputs), 3)
  for index in 0..<3 {
    let check = @context.local_input_closure_at(inputs, index).unwrap()
    assert_eq(check.subject.stage, 0)
    assert_eq(check.subject.name, "rows")
    assert_eq(@context.local_input_execution_phase(check), BeforeLocalInputUse)
    assert_eq(@context.local_input_execution_failure(check), RejectLocalInput)
  }
  for stage in 0..<2 {
    let pipeline = @program_check.unit_pipeline(program, stage).unwrap()
    assert_eq(@pipeline.step_count(pipeline), 1)
    let count = @program_check.unit_contract_count(program, stage).unwrap()
    assert_true(count > 0)
    for index in 0..<count {
      let (cid, body) = @program_check.unit_contract_at(program, stage, index).unwrap()
      assert_eq(cid, @context.core_contract_cid(body))
    }
    assert_true(@program_check.unit_contract_at(program, stage, count) is None)
    assert_eq(@program_check.unit_publication_count(program, stage), Some(1))
    let publication = @program_check.unit_publication_at(program, stage, 0).unwrap()
    let selected = @program_check.publication_selection(publication)
    assert_eq(@context.publication_row_limit_maximum(selected), 1000L)
    let result = @context.publication_row_limit_result(selected)
    assert_eq(result.stage, stage)
    assert_true(
      physical_equal(
        @pipeline.publication_pipeline(
          @publication.port_publication(result.port),
        ),
        pipeline,
      ),
    )
    let order = @publication.port_order(result.port)
    assert_eq(
      @publication.publication_strategy(order),
      if stage == 0 {
        CandidateKey
      } else {
        Inherited
      },
    )
    if stage == 1 {
      let retained = @publication.publication_inherited_order(order).unwrap()
      let producer = @pipeline.order_input_producer(retained).unwrap()
      assert_true(
        physical_equal(
          @pipeline.producer_pipeline(producer),
          @program_check.unit_pipeline(program, 0).unwrap(),
        ),
      )
    }
  }
  assert_true(@program_check.unit_pipeline(program, 2) is None)
  assert_true(@program_check.unit_publication_at(program, 2, 0) is None)
}

///|
fn public_source_limits(stage_count : Int) -> @program_check.SourceLimits {
  {
    topology: {
      max_stages: stage_count,
      max_steps: stage_count,
      max_results: stage_count,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    context: {
      stages: {
        max_work: 10000000,
        max_text_bytes: 10000000,
        max_name_bytes: 1000000,
        max_input_work: 1000000,
        max_operand_work: 1000000,
      },
      max_policy_bytes: 10000,
      max_policy_nodes: 100,
      max_policy_depth: 10,
      max_local_input_nodes: 100000,
    },
    requests: {
      max_work: 10000000,
      max_pairs: 1000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    },
    checks: {
      work: 10000000,
      text_bytes: 10000000,
      source_value_nodes: 1000000,
      source_comparison_pairs: 1000000,
      policy_nodes: 1000000,
      local_input_nodes: 1000000,
      pattern_ast_bytes: 1000000,
      pattern_ast_nodes: 1000000,
    },
    identity: {
      body: {
        max_work: 1000000,
        selectors: {
          max_nodes: 10000,
          max_depth: 100,
          max_text_bytes: 100000,
          max_tokens: 1000,
          tree: {
            max_nodes: 10000,
            max_depth: 100,
            max_string_bytes: 100000,
            max_total_string_bytes: 100000,
          },
        },
      },
      uses: {
        max_work: 1000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 100000,
        max_direct_text_bytes: 100000,
      },
      references: {
        max_work: 4000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 1000000,
        max_request_text_bytes: 100000,
      },
      identity: {
        max_work: 10000000,
        max_stages: stage_count,
        max_hash_bytes: 100000,
        max_hash_nodes: 10000,
        max_depth: 100,
      },
      max_bindings: 100,
    },
    max_parameters: 1,
    max_bindings: 100,
    max_slots: 1000,
    max_policy_depth: 100,
    max_requirements: 1000,
    max_regex_depth: 100,
  }
}
