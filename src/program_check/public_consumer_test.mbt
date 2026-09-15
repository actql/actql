///|
// Public test-package setup: no private constructor or reissued checked handle.
fn public_program_fixture(
  generated? : Bool = false,
  repeated? : Bool = false,
  max_work? : Int = 10000000,
  document? : Bool = false,
) -> @program_check.CheckedProgram raise {
  let (text, program, environment, evidence, limits) = public_input_fixture(
    generated~,
    repeated~,
  )
  let limits = {
    ..limits,
    compilation: { ..limits.compilation, work: max_work, },
  }
  if document {
    @program_check.check_document_with_evidence(
      text,
      environment,
      None,
      evidence,
      limits,
      format=Json,
      source_path="fixture.actql",
    )
  } else {
    @program_check.check_parsed_with_evidence(
      program,
      environment,
      None,
      evidence,
      limits,
    )
  }
}

///|
fn public_input_fixture(
  generated? : Bool = false,
  repeated? : Bool = false,
) -> (
  String,
  @syntax.Program,
  @program_check.CheckEnvironment,
  Array[@context.StageCapacityInput],
  @program_check.CheckLimits,
) {
  let text = (
      #|{"version":"actql/0.1","id":"public-reader","params":{"n":{"type":"number","default":1}},"stages":[{"id":"producer","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}},{"id":"consumer","inputs":{"rows":{"result":{"stage":"producer","result":"out"}}},"steps":[{"take":1,"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}}}],"results":{"out":{"from":{"stage":"consumer","result":"out"}}}}
    )
    .replace(
      old="\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":[",
      new=if generated {
        "\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]}},"
      } else {
        "\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":["
      },
    )
    .replace(
      old="{\"take\":1,\"as\":\"selected\"}",
      new=if repeated {
        "{\"append\":{\"with\":\"rows\"}},{\"distinct\":[\"id\",\"value\"],\"as\":\"selected\"}"
      } else {
        "{\"take\":1,\"as\":\"selected\"}"
      },
    )
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    tree: {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
    max_stages: 2,
  }
  let program = @syntax.parse(
    text,
    input_limits,
    format=Json,
    source_path="fixture.actql",
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
  let proofs = if generated { [public_seed_claim()] } else { [] }
  let mixed = @wire.check_mixed_claims(
    proofs.map(p => @wire.program_proof_witness(p)),
    [],
    {
      max_entities: 100,
      max_references: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
    max_witnesses: 100,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  // Explicit proofs target Stage definitions. The compiler, not this public
  // consumer, assigns them to the actual imported producer occurrences.
  let consumer_sources = if repeated {
    let all = [public_seed_claim(), public_append_claim()]
    let mixed = @wire.check_mixed_claims(
      all.map(p => @wire.program_proof_witness(p)),
      [],
      {
        max_entities: 100,
        max_references: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    ).unwrap()
    let claims = @wire.check_mixed_program_claims(mixed, all, {
      max_witnesses: 100,
      max_references: 100,
    }).unwrap()
    let sources = @host.bind_claim_sources(claims, [], {
      max_entries: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap()
    sources
  } else {
    sources
  }
  (
    text,
    program,
    @program_check.checking_environment(
      environment,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ),
    if generated || repeated {
      [
        { stage: "producer", sources, uses: [], },
        { stage: "consumer", sources: consumer_sources, uses: [], },
      ]
    } else {
      []
    },
    { input: input_limits, compilation: public_source_limits(2), },
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
fn public_source_limits(stage_count : Int) -> @program_check.CompileLimits {
  {
    work: 10000000,
    artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
    structure: {
      stages: stage_count,
      steps: 5,
      results: stage_count,
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
  }
}
