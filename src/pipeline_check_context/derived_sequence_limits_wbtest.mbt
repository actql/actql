///|
fn automatic_sequence_fixture(
  empty? : Bool = false,
  unused? : Bool = false,
  guarded? : Bool = false,
) -> (@syntax.Program, @stage_results.PreparedLocalSource) {
  let operation = "{\"from\":\"seed\",\"sequence\":{\"by\":[\"key\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"a\",\"where\":\"value = 1\"},{\"as\":\"b\",\"where\":\"value = 2\"}],\"within\":10,\"overlap\":\"allow\",\"contiguity\":\"subsequence\"" +
    (if guarded {
      ",\"max_matches_per_key\":2,\"max_output_rows\":3"
    } else {
      ""
    }) +
    "},\"as\":\"matched\"}"
  let text = (
      #|{"version":"actql/0.1","id":"automatic-sequence","stages":[{"id":"producer","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"key":{"type":"number","nullable":false},"clock":{"type":"number","nullable":false},"value":{"type":"number","nullable":false}},"rows":
    ) +
    (if empty {
      "[]"
    } else {
      "[{\"id\":1,\"key\":1,\"clock\":1,\"value\":1},{\"id\":2,\"key\":1,\"clock\":2,\"value\":2}]"
    }) +
    "},\"as\":\"seed\"}," +
    operation +
    (if unused {
      "," + operation.replace(old="\"as\":\"matched\"", new="\"as\":\"unused\"")
    } else {
      ""
    }) +
    (
      #|],"results":{"r":{"from":"matched","fields":["key","a_id","b_id"]}}},{"id":"consumer","inputs":{"x":{"result":{"stage":"producer","result":"r"}}},"steps":[{"select":["key","a_id","b_id"],"as":"out"}],"results":{"r":{"from":"out","fields":["key","a_id","b_id"]}}}],"results":{"r":{"from":{"stage":"consumer","result":"r"}}}}
    )
  let program = @syntax.parse(
    text,
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
  let prepared = @stage_results.prepare_local_source(
    program,
    None,
    max_parameters=0,
    {
      max_stages: 2,
      max_steps: 4,
      max_results: 3,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
  ).unwrap()
  (program, prepared)
}

///|
fn automatic_sequence_capacity(
  prepared : @stage_results.PreparedLocalSource,
  inputs : ProgramCapacityInputs,
  max_work? : Int = 1000000,
  max_bytes? : Int = 1000000,
  max_nodes? : Int = 100000,
) -> Result[DerivedProgramCapacity, CapacityStageIssue] {
  derive_program_capacity(
    prepared,
    inputs,
    max_work,
    { max_bytes, max_nodes, max_depth: 100, },
    100000,
    100000,
    capacity_count_bindings(@stage_results.local_source_values(prepared)),
    1000000,
    None,
    sequence_limit_policy(false),
  )
}

///|
test "automatic Sequence registers exact Host scopes including unused occurrences" {
  for
    (empty, unused, guarded) in [
      (false, false, false),
      (true, true, false),
      (false, false, true),
    ] {
    let (program, prepared) = automatic_sequence_fixture(
      empty~,
      unused~,
      guarded~,
    )
    let inputs = bind_capacity_inputs(program, [], 10000).unwrap()
    let generated = automatic_sequence_capacity(prepared, inputs).unwrap()
    let material = generated.inputs.materials[0]
    let port = @stage_results.wiring_stage_at(
      @stage_results.local_source_wiring(prepared),
      0,
    ).unwrap()
    let pipeline = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(
        @results.checked_producer_orders(
          @results.ports_orders(@stage_results.stage_port_publications(port)),
        ),
        0,
      ).unwrap(),
    )
    let claims = @host.source_claims(material.sources)
    let mixed = @wire.program_claim_mixed(claims).unwrap()
    let mut count = 0
    for consumer in material.consumers {
      if consumer is @capacity.Sequence(step~, matches~, output~) {
        count += 1
        for
          (index, suffix) in [(matches, "matches-per-key"), (output, "output")] {
          let claim = @wire.mixed_limit_at(mixed, index).unwrap()
          assert_eq(
            @wire.limit_subject(claim),
            "sequence:checked-step:" + step.to_string() + ":" + suffix,
          )
          assert_eq(@wire.limit_enforcement(claim), @wire.EngineAtomic)
          assert_eq(
            @derivation.minimum_value(@wire.limit_minimum(claim)),
            if suffix == "matches-per-key" {
              3L
            } else {
              7L
            },
          )
        }
        if !guarded {
          assert_true(
            @sequence_limits.check_host_limits(
              pipeline,
              step,
              material.sources,
              sequence_limit_policy(false),
              matches,
              output,
              max_work=10000,
            )
            is Ok(_),
          )
          assert_true(
            @sequence_limits.check_host_limits(
              pipeline,
              step,
              material.sources,
              sequence_limit_policy(false),
              output,
              matches,
              max_work=10000,
            )
            is Err(SubjectMismatch(_)),
          )
          assert_true(
            @sequence_limits.check_host_limits(
              pipeline,
              step,
              material.sources,
              sequence_limit_policy(true),
              matches,
              output,
              max_work=10000,
            )
            is Err(CandidateScopeMismatch(_, _)),
          )
        }
      }
    }
    assert_eq(count, if unused { 2 } else { 1 })
    let contexts = prepare_local_stage_contexts_from_inputs(
      prepared,
      generated.inputs,
      sequence_limit_policy(false),
      {
        max_work: 1000000,
        max_text_bytes: 1000000,
        max_name_bytes: 100000,
        max_input_work: 100000,
        max_operand_work: 100000,
      },
    ).unwrap()
    let coverage = @capacity.application_closure_at(
      contexts.contexts[0].context.capacity,
      0,
    ).unwrap()
    let applications = @capacity.consumer_coverage_sequence(
      @capacity.application_coverage_consumers(coverage),
    )
    let selected = @sequence_limits.application_at(applications, 1).unwrap()
    assert_eq(
      @sequence_limits.effective_maximum(
        selected,
        @sequence_limits.MatchesPerKey,
      ),
      if guarded {
        2L
      } else {
        3L
      },
    )
    assert_eq(
      @sequence_limits.effective_maximum(selected, @sequence_limits.OutputRows),
      if guarded {
        3L
      } else {
        7L
      },
    )
    let repeated = automatic_sequence_capacity(prepared, generated.inputs).unwrap()
    assert_true(
      physical_equal(repeated.inputs.materials[0].sources, material.sources),
    )
    assert_eq(
      repeated.inputs.materials[0].consumers.length(),
      material.consumers.length(),
    )
  }
}

///|
test "automatic Sequence does not replace supplied foreign application coordinates" {
  let (program, prepared) = automatic_sequence_fixture()
  // These admitted claims name checked-step:0, not this Sequence at step 1.
  let sources = sequence_limit_sources()
  let mixed = @wire.program_claim_mixed(@host.source_claims(sources)).unwrap()
  let inputs = bind_capacity_inputs(
    program,
    [
      {
        stage: "producer",
        sources,
        uses: [
          Sequence(
            step=1,
            matches=@wire.mixed_limit_at(mixed, 0).unwrap(),
            output=@wire.mixed_limit_at(mixed, 1).unwrap(),
          ),
        ],
      },
    ],
    10000,
  ).unwrap()
  let generated = automatic_sequence_capacity(prepared, inputs).unwrap()
  assert_true(
    prepare_local_stage_contexts_from_inputs(
      prepared,
      generated.inputs,
      sequence_limit_policy(false),
      {
        max_work: 1000000,
        max_text_bytes: 1000000,
        max_name_bytes: 100000,
        max_input_work: 100000,
        max_operand_work: 100000,
      },
    )
    is Err(Capacity(0, 0, Sequence(_, SubjectMismatch(_)))),
  )
}

///|
test "Sequence registration reuses completed applications at exact scan work" {
  let (program, prepared) = automatic_sequence_fixture()
  let inputs = bind_capacity_inputs(program, [], 10000).unwrap()
  let generated = automatic_sequence_capacity(prepared, inputs).unwrap()
  // Isolate only the registration pass, using normally derived claims. Two
  // material slots, one consumer and three authored steps require six visits.
  // There is no new wire/hash allocation when both limits are already supplied.
  let prior = RowCapacityResult::{
    materials: generated.inputs.materials,
    applications: [],
    work: 0,
    text: 0,
    bytes: 0,
    nodes: 0,
    input_work: 0,
    operand_work: 0,
  }
  for work in [6, 5] {
    let result = derive_sequence_limits(
      prepared,
      prior,
      work,
      { max_bytes: 0, max_nodes: 0, max_depth: 0, },
      sequence_limit_policy(false),
    )
    if work == 6 {
      let reused = result.unwrap()
      assert_eq(reused.work, 6)
      assert_eq((reused.bytes, reused.nodes), (0, 0))
      assert_true(
        physical_equal(reused.materials[0].sources, prior.materials[0].sources),
      )
      assert_eq(reused.materials[0].consumers.length(), 1)
    } else {
      assert_true(result is Err(BudgetExceeded))
    }
  }
}
