///|
// Input material for a known source ordinal, not output from Program checking.
fn local_sequence_capacity_fixture(
  environment : @environment.WireEnvironment,
  maximum : Int,
  step : Int,
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
  let mixed = @wire.check_mixed_claims(witnesses, limits, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
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
  let steps = sequence_test_steps(false, "disallow", "adjacent", "").replace(
    old="{\"$param\":\"n\"}",
    new="1",
  )
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
test "formal sequence rejects missing coverage and unbound authored limits without partial Programs" {
  for guard_text in ["", ",\"max_matches_per_key\":1", ",\"max_output_rows\":1"] {
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
