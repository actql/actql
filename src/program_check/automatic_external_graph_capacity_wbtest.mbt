///|
fn external_graph_checked_program(
  imported : Bool,
  repeated : Bool,
) -> CheckedProgram raise {
  let (environment, sources) = external_graph_capacity_fixture()
  let text =
    #|{"version":"actql/0.1","id":"external-graph","stages":[{"id":"s","inputs":{"g":{"connector":"crm/main","resource":"r"}},"steps":[{"match_nodes":{"definition":"N","label":"Node","where":"true","fields":["id"]},"as":"rows"}],"results":{"out":{"from":"rows","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let text = if imported {
    text.replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}",
      new="},{\"id\":\"consumer\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"s\",\"result\":\"out\"}}},\"steps\":" +
        (if repeated {
          "[{\"append\":{\"with\":\"rows\"}},{\"distinct\":[\"id\"],\"as\":\"selected\"}]"
        } else {
          "[]"
        }) +
        ",\"results\":{\"out\":{\"from\":\"" +
        (if repeated { "selected" } else { "rows" }) +
        "\",\"fields\":[\"id\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"consumer\",\"result\":\"out\"}}}}",
    )
  } else {
    text
  }
  let defaults = distinct_compile_limits()
  let outcome = check_document_with_evidence(
    text,
    checking_environment(
      environment,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      property_graph=true,
    ),
    None,
    [{ stage: "s", sources, uses: [], }],
    {
      input: {
        source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
        tree: {
          max_nodes: 1000,
          max_depth: 100,
          max_string_bytes: 10000,
          max_total_string_bytes: 10000,
        },
        max_stages: 10,
      },
      compilation: {
        ..defaults,
        work: 100000000,
        artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
        traversal: {
          nodes: 1000000,
          depth: 100,
          text_bytes: 10000000,
          string_bytes: 1000000,
          name_bytes: 1000000,
          pointer_units: 100000,
          comparison_pairs: 100000,
        },
        values: { nodes: 1000000, depth: 100, text_bytes: 10000000, },
        policy: { bytes: 1000000, nodes: 100000, depth: 100, },
      },
    },
    format=Json,
  )
  let program = match outcome {
    Checked(program) => program
    NeedsInputs(_) => fail("unexpected missing inputs")
    Rejected(diagnostic) =>
      match diagnostic_cause(diagnostic) {
        Environment(Carriers(issue)) =>
          fail("carrier " + @debug.to_string(issue.kind))
        Source(SourceView(Context(Stages(RowCapacity(InvalidGraph))))) =>
          fail(
            "automatic capacity cannot register the foreign Graph input owner",
          )
        Source(SourceView(Context(Stages(Capacity(stage, visit, issue))))) =>
          fail(
            "capacity " +
            stage.to_string() +
            "/" +
            visit.to_string() +
            " " +
            @debug.to_string(issue),
          )
        Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
          fail("pipeline " + @debug.to_string(issue.kind))
        Source(Registration(Selection(issue))) =>
          fail("selection " + @debug.to_string(issue.kind))
        Source(Registration(Registration(issue))) =>
          fail("registration " + @debug.to_string(issue))
        Source(Registration(Declarations(_))) => fail("input declarations")
        Source(Registration(LocalInputs(_))) => fail("local inputs")
        Source(issue) => raise issue
        other => raise other
      }
  }
  program
}

///|
test "Property Graph source derives MATCH proof from admitted input enforcement" {
  for imported in [false, true] {
    let program = external_graph_checked_program(imported, false)
    let publication = unit_publication_at(
      program,
      if imported {
        1
      } else {
        0
      },
      0,
    ).unwrap()
    assert_true(publication_proof_count(publication) > 0)
    let proof = publication_proof_at(publication, 0).unwrap()
    assert_eq(@wire.value(@wire.program_proof_witness(proof_claim(proof))), 1L)
    assert_eq(proof_graph_input_count(proof), 1)
  }
}

///|
test "imported Graph-derived rows keep input enforcement through repeated append" {
  let program = external_graph_checked_program(true, true)
  let publication = unit_publication_at(program, 1, 0).unwrap()
  assert_true(publication_proof_count(publication) > 0)
  let proof = publication_proof_at(publication, 0).unwrap()
  assert_eq(@wire.value(@wire.program_proof_witness(proof_claim(proof))), 2L)
  assert_eq(proof_input_count(proof), 2)
  let first = proof_input_at(proof, 0).unwrap()
  let second = proof_input_at(proof, 1).unwrap()
  assert_true(physical_equal(first, second))
  assert_eq(proof_graph_input_count(first), 1)
  assert_eq(
    proof_source(proof).unit_definition_cid,
    unit_definition_cid(program, 1).unwrap(),
  )
  assert_eq(
    proof_source(first).unit_definition_cid,
    unit_definition_cid(program, 0).unwrap(),
  )
}

///|
test "Graph MATCH operands retain producer ownership before material collection" {
  let program = external_graph_checked_program(true, false)
  let source = program.units[0].pipeline
  let candidate = @context.publication_row_limit_program_at(
    program.units[0].publication_rows[0],
    0,
  ).unwrap()
  let bound = @step_bounds.target_rows_bound(
    @capacity.target_membership_rows(candidate.membership),
  )
  let input = @pipeline.produced_input(source, Step(0)).unwrap()
  let limits : @pipeline.Limits = {
    max_steps: 10,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 100000,
    max_tokens: 100000,
    max_depth: 100,
  }
  let consumer = @pipeline.check_with_evidence(
    supplied_fixture("[{\"append\":{\"with\":\"rows\"}}]"),
    [("rows", ProducedInput(input))],
    None,
    None,
    limits,
  ).unwrap()
  let caps : @step_bounds.DeriveBoundLimits = {
    max_input_work: 100000,
    max_operand_work: 100000,
    max_reference_work: 100000,
    metadata: { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  }
  let derived = @step_bounds.derive_bound(
    consumer,
    0,
    [StepInput(bound), StepInput(bound)],
    caps,
  ).unwrap()
  assert_eq(
    @wire.value(
      @wire.program_proof_witness(@step_bounds.checked_proof(derived.bound)),
    ),
    2L,
  )
  assert_eq(@step_bounds.input_count(derived.bound), 2)
  for index in 0..<2 {
    assert_true(
      physical_equal(
        @step_bounds.input_at(derived.bound, index).unwrap(),
        bound,
      ),
    )
  }
  // Identical source text and proof bodies from a different check do not grant
  // this consumer access to that other Program's Graph input enforcement.
  let foreign = external_graph_checked_program(true, false)
  let foreign_candidate = @context.publication_row_limit_program_at(
    foreign.units[0].publication_rows[0],
    0,
  ).unwrap()
  let foreign_bound = @step_bounds.target_rows_bound(
    @capacity.target_membership_rows(foreign_candidate.membership),
  )
  assert_eq(
    @wire.cid(@wire.program_proof_witness(@step_bounds.checked_proof(bound))),
    @wire.cid(
      @wire.program_proof_witness(@step_bounds.checked_proof(foreign_bound)),
    ),
  )
  assert_true(
    @step_bounds.derive_bound(
      consumer,
      0,
      [StepInput(bound), StepInput(foreign_bound)],
      caps,
    )
    is Err(Application(InputOwnerMismatch(1))),
  )
}

///|
test "imported Graph limit scope requires retained source admission and bounded registration" {
  let program = external_graph_checked_program(true, true)
  let context = @context.publication_row_limit_result(
      program.units[1].publication_rows[0],
    ).context
  let closure = @context.checked_capacity(context)
  let graph = @capacity.source_coverage_graph(
    @capacity.application_coverage_sources(
      @capacity.application_closure_at(closure, 0).unwrap(),
    ),
  )
  let producer = @graph_input.dependency_at(graph, 0).unwrap()
  assert_eq(@graph_input.dependency_count(graph), 1)
  let sources = @graph_input.checked_sources(graph)
  let pipeline = @graph_input.checked_pipeline(graph)
  let policy = @graph_input.selected_policy(graph)
  assert_eq(@host.source_local_limit_count(sources), 0)
  assert_eq(
    @wire.mixed_limit_count(
      @wire.program_claim_mixed(@host.source_claims(sources)).unwrap(),
    ),
    2,
  )
  // Consumer has one non-Graph input and no local Graph preflight. The two
  // imported limits are consumed by the producer, not by a renamed local input.
  let expected = @pipeline.input_count(pipeline) * 2 +
    @wire.claim_count(
      @wire.program_claim_arithmetic(@host.source_claims(sources)),
    ) +
    3
  let caps : @graph_input.Limits = { max_work: expected, max_name_bytes: 4, }
  let checked = @graph_input.check(pipeline, sources, policy, caps, producers=[
    producer,
  ]).unwrap()
  assert_eq(@graph_input.usage(checked).0, expected)
  assert_eq(@graph_input.unconsumed_limit_count(checked), 0)
  assert_true(
    @graph_input.check(pipeline, sources, policy, caps)
    is Err(ForeignDependency(0)),
  )
  assert_true(
    @graph_input.check(
      pipeline,
      sources,
      policy,
      { ..caps, max_work: expected - 1, },
      producers=[producer],
    )
    is Err(BudgetExceeded),
  )
  let other = external_graph_checked_program(true, true)
  let other_context = @context.publication_row_limit_result(
      other.units[1].publication_rows[0],
    ).context
  let other_graph = @capacity.source_coverage_graph(
    @capacity.application_coverage_sources(
      @capacity.application_closure_at(
        @context.checked_capacity(other_context),
        0,
      ).unwrap(),
    ),
  )
  let foreign = @graph_input.dependency_at(other_graph, 0).unwrap()
  assert_true(
    @graph_input.check(pipeline, sources, policy, caps, producers=[foreign])
    is Err(ForeignDependency(0)),
  )
  let detached = @graph_input.check(
    @graph_input.checked_pipeline(producer),
    @graph_input.checked_sources(producer),
    policy,
    { max_work: 100000, max_name_bytes: 1000, },
  ).unwrap()
  let detached_consumer = @graph_input.check(pipeline, sources, policy, caps, producers=[
    detached,
  ]).unwrap()
  let original = @capacity.application_closure_at(closure, 0).unwrap()
  let consumers = @capacity.application_coverage_consumers(original)
  let replacement = @capacity.check_application_coverage(
    detached_consumer,
    @capacity.source_coverage_program(
      @capacity.application_coverage_sources(original),
    ),
    @capacity.consumer_coverage_sequence(consumers),
    joins=@capacity.consumer_coverage_joins(consumers),
    traversals=@capacity.consumer_coverage_traversals(consumers),
    max_work=100000,
  ).unwrap()
  assert_true(
    @capacity.check_application_closure(
      @capacity.application_closure_orders(closure),
      [replacement, @capacity.application_closure_at(closure, 1).unwrap()],
      selected_policy=policy,
      bound_guards=@capacity.application_closure_guards(closure),
      max_work=1000000,
    )
    is Err(ForeignGraphDependency(0, 0)),
  )
  let union_caps : @wire.ClosureLimits = {
    max_witnesses: 100,
    max_references: 1000,
  }
  let nested = @host.extend_source_dependencies(
      @graph_input.checked_sources(producer),
      [@graph_input.checked_sources(foreign)],
      [],
      union_caps,
      max_work=100000,
    ).unwrap().0
  let local_sources = @host.bind_claim_sources(
    @host.source_origin_claims(sources),
    [],
    { max_entries: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let transitive = @host.extend_source_dependencies(
      local_sources,
      [nested],
      [],
      union_caps,
      max_work=100000,
    ).unwrap().0
  // A supplied dependency can itself retain another source origin. Equal wire
  // bodies do not erase the obligation to register that transitive owner.
  assert_eq(@host.source_dependency_count(transitive), 2)
  assert_true(
    @graph_input.check(
      pipeline,
      transitive,
      policy,
      { max_work: 100000, max_name_bytes: 1000, },
      producers=[producer],
    )
    is Err(ForeignDependency(1)),
  )
}
