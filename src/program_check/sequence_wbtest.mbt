///|
// Input material for a known source ordinal, not output from Program checking.
fn local_sequence_capacity_fixture(
  environment : @environment.WireEnvironment,
  maximum : Int,
  step : Int,
  output_proof? : Bool = false,
) -> @host.HostSources raise @encode.EncodeFailure {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let witnesses = []
  let limits = []
  for
    (field, unit, suffix) in [
      ("max_temporal_matches_per_key", "matches_per_key", "matches-per-key"),
      ("max_temporal_output_rows", "rows", "output"),
    ] {
    let host = @host.create(@policy.ceiling(policy, field).unwrap(), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let writer = @encode.writer(10000, 1000, 30)
    @host.emit(host, writer)
    let host_text = @encode.finish(writer)
    witnesses.push(
      @wire.admit(@utf8.encode(host_text), @host.cid(host), {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 30,
      }).unwrap(),
    )
    let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      host_text +
      "],\"effective_max\":" +
      maximum.to_string() +
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"sequence:checked-step:" +
      step.to_string() +
      ":" +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    let text = body.replace(
      old="\"subject_ref\":",
      new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
    )
    limits.push((@utf8.encode(text), cid))
  }
  let proofs : Array[@wire.ProgramProofClaim] = []
  if output_proof {
    let proof = sequence_fixture_proof(
      "actql.bound.sequence-output",
      step,
      maximum,
      [@wire.cid(witnesses[1])],
      "{\"op\":\"source\"}",
    )
    proofs.push(proof)
    witnesses.push(@wire.program_proof_witness(proof))
  }
  let mixed = @wire.check_mixed_claims(witnesses, limits, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
    max_witnesses: 10,
    max_references: 20,
  }).unwrap()
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 10,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
}

///|
fn sequence_test_steps(
  events : Bool,
  overlap : String,
  contiguity : String,
  guard_text : String,
) -> String {
  "[" +
  (if events {
    "{\"to_events\":{\"id\":\"id\",\"time\":\"value\"}},"
  } else {
    ""
  }) +
  "{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"value\",\"pattern\":[{\"as\":\"a\",\"where\":\"TRUE\"},{\"as\":\"b\",\"where\":\"TRUE\"}],\"within\":{\"$param\":\"n\"},\"overlap\":\"" +
  overlap +
  "\",\"contiguity\":\"" +
  contiguity +
  "\"" +
  guard_text +
  "}},{\"select\":[{\"id\":\"a_id\"},{\"value\":\"b_id\"}],\"as\":\"selected\"}]"
}

///|
test "formal sequence closes temporal input matching and atomic limits through a Result import" {
  for events in [false, true] {
    for empty in [false, true] {
      for overlap in ["allow", "disallow"] {
        for contiguity in ["adjacent", "subsequence"] {
          let checked : Array[CheckedProgram] = []
          let _ = local_construction_fixture(
            { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
            through_check=true,
            checked_results=checked,
            second_stage=true,
            parameters=true,
            tea=true,
            second_sequence_capacity=true,
            second_sequence_step=if events { 1 } else { 0 },
            generated_rows=if empty { Some("[]") } else { None },
            second_steps=sequence_test_steps(events, overlap, contiguity, ""),
            second_result_from="selected",
            extra_step_budget=3,
          )
          assert_eq(checked.length(), 1)
          let program = checked[0]
          assert_eq(unit_count(program), 2)
          assert_eq(unit_sequence_limit_count(program, 0), Some(0))
          assert_eq(unit_sequence_limit_count(program, 1), Some(1))
          assert_true(unit_sequence_limit_at(program, 1, -1) is None)
          assert_true(unit_sequence_limit_at(program, 1, 1) is None)
          let bound = unit_sequence_limit_at(program, 1, 0).unwrap()
          let ordinal = if events { 1 } else { 0 }
          for
            (scope, suffix) in [
              (@sequence.MatchesPerKey, "matches-per-key"),
              (OutputRows, "output"),
            ] {
            let claim = sequence_limit_claim(bound, scope)
            assert_eq(
              @wire.limit_subject(claim),
              "unit:" +
              unit_definition_cid(program, 1).unwrap() +
              "#/steps/" +
              ordinal.to_string() +
              "/sequence/" +
              suffix,
            )
            assert_true(
              @wire.limit_cid(claim) !=
              @wire.limit_cid(
                @sequence.limit(sequence_limit_selection(bound).limits, scope),
              ),
            )
            assert_true(
              physical_equal(
                sequence_limit_source(bound).pipeline,
                unit_pipeline(program, 1).unwrap(),
              ),
            )
          }
          let pipeline = unit_pipeline(program, 1).unwrap()
          let closure = @context.stage_requirement_operations(
            requirements(program),
          )
          let mut inputs = 0
          let mut matching = 0
          let mut limits = 0
          for i in 0..<@context.operation_closure_count(closure) {
            guard @context.operation_closure_at(closure, i)
              is Some(ExecutionCheck(check)) else {
              continue
            }
            match check {
              SequenceExecution(v) => {
                inputs += 1
                assert_eq(v.site.stage, 1)
                assert_true(physical_equal(v.site.pipeline, pipeline))
              }
              SequenceMatch(v) => {
                matching += 1
                assert_eq(v.within_ms, 1L)
                assert_true(v.within_resolution is Some(_))
                assert_true(physical_equal(v.site.pipeline, pipeline))
              }
              SequenceLimits(v) => {
                limits += 1
                assert_eq(v.site.stage, 1)
                assert_true(physical_equal(v.site.pipeline, pipeline))
                assert_eq(
                  @context.operation_execution_phase(check),
                  BeforeOperationOutput,
                )
                assert_eq(
                  @context.operation_execution_failure(check),
                  RejectOperationOutput,
                )
              }
              _ => ()
            }
          }
          assert_eq((inputs, matching, limits), (3, 1, 1))
          assert_eq(unit_publication_count(program, 1), Some(1))
          assert_true(
            unit_definition_cid(program, 0) != unit_definition_cid(program, 1),
          )
        }
      }
    }
  }
}

///|
test "formal sequence limit imports retain the producer Unit instead of the consumer namespace" {
  let steps = sequence_test_steps(
    false, "disallow", "adjacent", ",\"max_output_rows\":2",
  ).replace(old="{\"$param\":\"n\"}", new="1")
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    through_check=true,
    checked_results=checked,
    second_stage=true,
    tea=true,
    second_sequence_capacity=true,
    sequence_capacity_stage=0,
    second_sequence_step=1,
    producer_suffix="," +
      steps.unsafe_substring(start=1, end=steps.length() - 1),
    producer_result_from="selected",
    extra_step_budget=2,
  )
  let program = checked[0]
  assert_eq(unit_sequence_limit_count(program, 0), Some(1))
  assert_eq(unit_sequence_limit_count(program, 1), Some(0))
  let limit = unit_sequence_limit_at(program, 0, 0).unwrap()
  assert_true(
    physical_equal(
      sequence_limit_source(limit).pipeline,
      unit_pipeline(program, 0).unwrap(),
    ),
  )
  assert_eq(
    @wire.limit_subject(sequence_limit_claim(limit, @sequence.OutputRows)),
    "unit:" +
    unit_definition_cid(program, 0).unwrap() +
    "#/steps/1/sequence/output",
  )
  let closure = @context.stage_requirement_operations(requirements(program))
  let output = sequence_limit_claim(limit, @sequence.OutputRows)
  let mut authored = 0
  for i in 0..<@derivation.minimum_candidate_count(@wire.limit_minimum(output)) {
    let node = @derivation.minimum_candidate_at(@wire.limit_minimum(output), i).unwrap().node
    let witness = @wire.claim_at(@wire.limit_claims(output), node).unwrap()
    if @wire.source(witness) is @wire.AuthorGuard(path, owner) {
      authored += 1
      assert_eq(path, "$.steps[1].sequence.max_output_rows")
      assert_eq(owner, unit_definition_cid(program, 0).unwrap())
      assert_true(owner != unit_definition_cid(program, 1).unwrap())
    }
  }
  assert_eq(authored, 1)
  let mut visits = 0
  for i in 0..<@context.operation_closure_count(closure) {
    if @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(SequenceLimits(v))) {
      visits += 1
      assert_true(
        physical_equal(v.site.pipeline, unit_pipeline(program, 0).unwrap()),
      )
    }
  }
  assert_eq(visits, 3)
}

///|
test "formal sequence rejects missing coverage without partial Programs" {
  for guard_text in [""] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        second_stage=true,
        parameters=true,
        tea=true,
        second_sequence_capacity=guard_text != "",
        second_steps=sequence_test_steps(
          false, "allow", "subsequence", guard_text,
        ),
        second_result_from="selected",
        extra_step_budget=2,
      )
    catch {
      LocalConstructionFailure::Source(
        SourceFailure::SourceView(Context(Stages(Capacity(1, 0, issue))))
      ) =>
        if guard_text == "" {
          assert_true(issue is SequenceCollection(MissingApplication(0)))
        } else {
          assert_true(issue is Sequence(0, UnresolvedAuthorSource(_)))
        }
      error => raise error
    } noraise {
      _ => fail("unresolved limits escaped")
    }
    assert_eq(checked.length(), 0)
  }
}

///|
test "formal sequence closes literal and Parameter guards into producer Unit limits" {
  for empty in [false, true] {
    for
      (token, expected) in [
        ("1", 1L),
        ("1000", 1000L),
        ("1001", 1001L),
        ("{\"$param\":\"n\"}", 1L),
      ] {
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        second_stage=true,
        parameters=true,
        tea=true,
        second_sequence_capacity=true,
        generated_rows=if empty { Some("[]") } else { None },
        second_steps=sequence_test_steps(
          false,
          "allow",
          "subsequence",
          ",\"max_matches_per_key\":" + token + ",\"max_output_rows\":" + token,
        ),
        second_result_from="selected",
        extra_step_budget=2,
      )
      assert_eq(checked.length(), 1)
      let program = checked[0]
      let selection = unit_sequence_limit_at(program, 1, 0).unwrap()
      let owner = unit_definition_cid(program, 1).unwrap()
      for
        (scope, field, host) in [
          (@sequence.MatchesPerKey, "max_matches_per_key", 1000L),
          (OutputRows, "max_output_rows", 1000L),
        ] {
        let claim = sequence_limit_claim(selection, scope)
        let minimum = @wire.limit_minimum(claim)
        assert_eq(
          @derivation.minimum_value(minimum),
          Int64::min(expected, host),
        )
        assert_eq(@derivation.minimum_candidate_count(minimum), 2)
        let first = @derivation.minimum_candidate_at(minimum, 0).unwrap()
        let guard_index = if @wire.source(
            @wire.claim_at(@wire.limit_claims(claim), first.node).unwrap(),
          )
          is @wire.AuthorGuard(_, _) {
          0
        } else {
          1
        }
        let candidate = @derivation.minimum_candidate_at(minimum, guard_index).unwrap()
        let witness = @wire.claim_at(@wire.limit_claims(claim), candidate.node).unwrap()
        assert_eq(@wire.value(witness), expected)
        assert_eq(
          @wire.source(witness),
          @wire.AuthorGuard("$.steps[0].sequence." + field, owner),
        )
        let original = @sequence.host_limit(
          sequence_limit_selection(selection).limits,
          scope,
        )
        let original_node = @derivation.minimum_candidate_at(
            @wire.limit_minimum(original),
            0,
          ).unwrap().node
        let retained_node = @derivation.minimum_candidate_at(
            minimum,
            1 - guard_index,
          ).unwrap().node
        assert_eq(
          @wire.cid(
            @wire.claim_at(@wire.limit_claims(claim), retained_node).unwrap(),
          ),
          @wire.cid(
            @wire.claim_at(@wire.limit_claims(original), original_node).unwrap(),
          ),
        )
        assert_true(@wire.limit_cid(claim) != @wire.limit_cid(original))
      }
    }
  }
}

///|
test "formal sequence rejects invalid within binding even for empty imported inputs" {
  for value in ["0", "-1", "0.5", "9007199254740992"] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        second_stage=true,
        parameters=true,
        tea=true,
        second_sequence_capacity=true,
        generated_rows=Some("[]"),
        supplied=Some(supplied_fixture("{\"n\":" + value + "}")),
        second_steps=sequence_test_steps(false, "disallow", "adjacent", ""),
        second_result_from="selected",
        extra_step_budget=2,
      )
    catch {
      LocalConstructionFailure::Closure(
        Operations(Scalars(InvalidValue(_, Milliseconds("n", signed=false))))
      ) => ()
      error => raise error
    } noraise {
      _ => fail("invalid within escaped")
    }
    assert_eq(checked.length(), 0)
  }
}
