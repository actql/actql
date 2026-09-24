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
  let outcome = if document {
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
  public_checked(outcome)
}

///|
fn public_checked(
  outcome : @program_check.CheckOutcome,
) -> @program_check.CheckedProgram raise {
  match outcome {
    Checked(program) => program
    NeedsInputs(_) => fail("fixture has missing inputs")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
}

///|
test "checked Program retains its exact admitted Environment owner" {
  let (_, source, configured, evidence, limits) = public_input_fixture()
  let checked = public_checked(
    @program_check.check_parsed_with_evidence(
      source,
      configured,
      None,
      evidence,
      limits,
    ),
  )
  let retained = @program_check.checked_environment(checked)
  let references = @program_check.checked_catalog_references(checked)
  assert_true(
    physical_equal(
      @environment.contract_registry_environment(
        @environment.catalog_registry(
          @environment.reference_contents(references),
        ),
      ),
      retained,
    ),
  )
  assert_true(
    physical_equal(
      retained,
      @program_check.checking_environment_wire(configured),
    ),
  )
  let (_, _, foreign, _, _) = public_input_fixture()
  assert_eq(
    @environment.cid(retained),
    @environment.cid(@program_check.checking_environment_wire(foreign)),
  )
  assert_false(
    physical_equal(retained, @program_check.checking_environment_wire(foreign)),
  )
}

///|
test "Effect computation candidate retains owners without admitting execution" {
  let (plain, _, environment, evidence, limits) = public_input_fixture()
  let text = plain.replace(
    old="\"id\":\"consumer\",\"inputs\":",
    new="\"id\":\"consumer\",\"effects\":{\"save\":{\"store\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.store.v1\",\"from\":{\"result\":\"out\"}}}},\"inputs\":",
  )
  let program = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="effect-fixture.actql",
  ).unwrap()
  match
    @program_check.check_parsed_with_evidence(
      program,
      environment,
      None,
      evidence,
      limits,
    ) {
    Rejected(diagnostic) =>
      match @program_check.diagnostic_cause(diagnostic) {
        Source(UnsupportedEffects(_)) => ()
        _ => fail("ordinary checker admitted an unclosed Effect")
      }
    _ => fail("ordinary checker admitted an unclosed Effect")
  }
  let candidate = @program_check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    evidence,
    limits,
    1,
    1,
  ).unwrap()
  let headers = @program_check.effect_computation_headers(candidate)
  assert_true(physical_equal(@syntax.effect_headers_owner(headers), program))
  assert_eq(@syntax.effect_header_count(headers), 1)
  assert_eq(
    @syntax.effect_header_kind(@syntax.effect_header_at(headers, 0).unwrap()),
    "store",
  )
  let results = @program_check.effect_computation_stage_results(candidate)
  let source = @stages.operations_source(@results.operations(results))
  assert_eq(@stages.stage_count(source), 2)
  assert_true(
    @publication.lookup(@results.stage_at(results, 1).unwrap(), "out")
    is Some(_),
  )
  let bound = @results.bind_effect_results(headers, results, 100).unwrap()
  assert_eq(@results.effect_result_binding_count(bound), 1)
  assert_true(
    physical_equal(
      @program_check.effect_computation_environment(candidate),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let references = @program_check.effect_computation_catalog_references(
    candidate,
  )
  assert_true(
    physical_equal(
      @environment.contract_registry_environment(
        @environment.catalog_registry(
          @environment.reference_contents(references),
        ),
      ),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let mappings = @environment.check_mapping_contract_shapes(
    @program_check.effect_computation_environment(candidate),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
    1000,
  ).unwrap()
  assert_true(
    @program_check.prepare_effect_computation_static(candidate, mappings, {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    })
    is Err(_),
  )
  match
    @program_check.prepare_effect_computation_candidate(
      program,
      environment,
      None,
      evidence,
      limits,
      1,
      0,
    ) {
    Err(Headers(issue)) =>
      assert_eq(@syntax.effect_header_issue_kind(issue), BudgetExceeded)
    _ => fail("unmetered Effect header escaped")
  }
  let (_, plain_program, _, _, _) = public_input_fixture()
  assert_true(
    @program_check.prepare_effect_computation_candidate(
      plain_program,
      environment,
      None,
      evidence,
      limits,
      1,
      1,
    )
    is Err(MissingEffects),
  )
  let malformed = @syntax.parse(
    text.replace(
      old="\"store\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.store.v1\",\"from\":{\"result\":\"out\"}}",
      new="\"store\":{}",
    ),
    limits.input,
    format=Json,
  ).unwrap()
  assert_true(
    @program_check.prepare_effect_computation_candidate(
      malformed,
      environment,
      None,
      evidence,
      limits,
      1,
      1,
    )
    is Err(Headers(_)),
  )
  let with_bindings = @syntax.parse(
    text.replace(
      old="\"id\":\"public-reader\",",
      new="\"id\":\"public-reader\",\"bindings\":{\"b\":{\"type\":\"string\"}},",
    ),
    limits.input,
    format=Json,
  ).unwrap()
  match
    @program_check.prepare_effect_computation_candidate(
      with_bindings,
      environment,
      None,
      evidence,
      limits,
      1,
      1,
    ) {
    Err(Computation(Source(UnsupportedBindings(_)))) => ()
    _ => fail("Effect candidate bypassed the unrelated binding audit")
  }
}

///|
fn public_input_fixture(
  generated? : Bool = false,
  repeated? : Bool = false,
  analytic_policy? : Bool = false,
  graph_policy? : Bool = false,
  text_policy? : (String, String)? = None,
  text_profile? : Bool = true,
  lexical_selection? : (String, String)? = None,
  lexical_profile? : Bool = false,
  calendar_selection? : (String, String)? = None,
  calendar_profile? : Bool = false,
  numeric_profile? : @numeric.Profile? = None,
  temporal_join_step? : Int? = None,
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
  let environment_cid = if calendar_selection is Some((_, cid)) {
    cid
  } else if lexical_selection is Some((_, cid)) {
    cid
  } else if text_policy is Some((_, cid)) {
    cid
  } else if graph_policy {
    "sha256:0e1e713a191318e1e3a418ca4c104e93dc6d32c9425096eda1a3ad004a7c6792"
  } else if analytic_policy {
    "sha256:04185e37572a0a791a18909c4bc09da47f393976a9b6bb940ed9658a0497de07"
  } else {
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904"
  }
  let environment = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
      .replace(
        old="\"host_policy_profile\":{\"capacity\":",
        new=if calendar_selection is Some((body, _)) {
          "\"host_policy_profile\":{\"calendar\":" + body + ",\"capacity\":"
        } else {
          "\"host_policy_profile\":{\"capacity\":"
        },
      )
      .replace(
        old="\"version\":\"actql-capacity-host-policy/0.1\"}",
        new=if lexical_selection is Some((body, _)) {
          "\"version\":\"actql-capacity-host-policy/0.1\"},\"text_rank\":" +
          body
        } else if text_policy is Some((body, _)) {
          "\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":" +
          body
        } else {
          "\"version\":\"actql-capacity-host-policy/0.1\"}"
        },
      )
      .replace(
        old="sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
        new=environment_cid,
      )
      .replace(
        old="\"max_artifact_bytes\":1000",
        new=if analytic_policy {
          "\"max_analytic_frame_memberships\":1000,\"max_analytic_input_wire_bytes\":1000,\"max_analytic_output_wire_bytes\":1000,\"max_analytic_partition_wire_bytes\":1000,\"max_artifact_bytes\":1000"
        } else {
          "\"max_artifact_bytes\":1000"
        },
      )
      .replace(
        old="\"max_graph_input_edges\":1000",
        new=if graph_policy {
          "\"max_graph_construction_edges\":1000,\"max_graph_construction_input_rows\":1000,\"max_graph_construction_nodes\":1000,\"max_graph_input_edges\":1000"
        } else {
          "\"max_graph_input_edges\":1000"
        },
      ),
    ),
    environment_cid,
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
      { text_time: text_profile && text_policy is Some(_), veca: false, },
      {
        rela: true,
        sga: graph_policy,
        tea: temporal_join_step is Some(_) || calendar_profile,
        calendar: calendar_profile,
        text_rank: lexical_profile,
      },
      numeric_profile~,
    ),
    if temporal_join_step is Some(step) {
      [
        public_search_capacity(environment, step) catch {
          _ => abort("invalid temporal search fixture capacity")
        },
      ]
    } else if generated || repeated {
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
    assert_eq(
      @context.publication_row_limit_maximum(selected),
      if stage == 0 {
        1000L
      } else {
        1L
      },
    )
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
test "external consumer receives the exact checked Result owner" {
  let program = public_program_fixture()
  let results = @program_check.checked_stage_results(program)
  let source = @stages.operations_source(@results.operations(results))
  assert_eq(@stages.stage_count(source), 2)
  for index in 0..<2 {
    let stage = @results.stage_at(results, index).unwrap()
    assert_true(@publication.lookup(stage, "out") is Some(_))
  }
  assert_true(@results.stage_at(results, 2) is None)
  let identity = @program_check.source_identity(program)
  let sources = @context.program_identity_sources(identity)
  let operations = @context.program_sources_operations(sources)
  let preparation = @context.operation_profiles_preparation(operations)
  let producers = @context.preparation_sources(preparation)
  let capacity = @context.source_producer_capacity(producers)
  let policy = @context.source_capacity_context(capacity)
  let selected = @context.source_policy_selected(policy)
  let reconciled = @context.policy_context(selected)
  let wired = @context.reconciled_wiring(reconciled)
  assert_true(
    physical_equal(
      results,
      @context.stage_results(@context.wired_stage_contexts(wired)),
    ),
  )
  let other = public_program_fixture()
  assert_false(
    physical_equal(results, @program_check.checked_stage_results(other)),
  )
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
