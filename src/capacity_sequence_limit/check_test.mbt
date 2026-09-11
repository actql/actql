///|
fn pipeline(
  events : Bool,
  overlap : String,
  guard_text : String,
) -> @pipeline.CheckedPipeline {
  let prefix = if events {
    "{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},"
  } else {
    ""
  }
  let text = "[" +
    prefix +
    "{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1,\"overlap\":\"" +
    overlap +
    "\",\"contiguity\":\"adjacent\"" +
    guard_text +
    "}}]"
  pipeline_text(text)
}

///|
fn pipeline_text(text : String) -> @pipeline.CheckedPipeline {
  let source = @source.parse_json(text, {
    max_input_bytes: 4096,
    max_nodes: 100,
    max_depth: 20,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 100,
    max_depth: 20,
    max_string_bytes: 4096,
    max_total_string_bytes: 4096,
  }).unwrap()
  let schema = @schema.from_object(
    @contract.object_contract(
      [("id", @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  @pipeline.check(cursor, [("rows", schema)], None, None, {
    max_steps: 2,
    max_work: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
  }).unwrap()
}

///|
test "sequence consumes independent per-key and output Host limits on both Carriers" {
  for events in [false, true] {
    let step = if events { 1 } else { 0 }
    for overlap in ["allow", "disallow"] {
      let p = pipeline(events, overlap, "")
      for repeated in [false, true] {
        let sources = fixtures(if repeated { 4 } else { 0 }, step)
        let selected = policy(false)
        let used = if repeated { 5 } else { 4 }
        let checked = @capacity_sequence_limit.check_host_limits(
          p,
          step,
          sources,
          selected,
          0,
          1,
          max_work=used,
        ).unwrap()
        assert_true(
          physical_equal(@capacity_sequence_limit.checked_pipeline(checked), p),
        )
        assert_true(
          physical_equal(
            @capacity_sequence_limit.checked_sources(checked),
            sources,
          ),
        )
        assert_true(
          physical_equal(
            @capacity_sequence_limit.selected_policy(checked),
            selected,
          ),
        )
        assert_eq(@capacity_sequence_limit.checked_step(checked), step)
        assert_eq(@capacity_sequence_limit.usage(checked), used)
        for
          (scope, value, index) in [
            (@capacity_sequence_limit.MatchesPerKey, 3L, 0),
            (OutputRows, 7L, 1),
          ] {
          let limit = @capacity_sequence_limit.limit(checked, scope)
          assert_eq(
            @arithmetic.minimum_value(@wire.limit_minimum(limit)),
            value,
          )
          assert_eq(@wire.limit_enforcement(limit), @wire.EngineAtomic)
          assert_eq(@capacity_sequence_limit.limit_index(checked, scope), index)
        }
        assert_true(
          @capacity_sequence_limit.check_host_limits(
            p,
            step,
            sources,
            selected,
            0,
            1,
            max_work=used - 1,
          )
          is Err(WorkLimit),
        )
        assert_true(
          @capacity_sequence_limit.check_host_limits(
            p,
            step,
            sources,
            selected,
            1,
            0,
            max_work=10,
          )
          is Err(SubjectMismatch(MatchesPerKey)),
        )
        assert_true(
          @capacity_sequence_limit.check_host_limits(
            p,
            step,
            sources,
            selected,
            0,
            0,
            max_work=10,
          )
          is Err(SubjectMismatch(OutputRows)),
        )
        guard @pipeline.step_at(p, step).unwrap().operation is Sequence(op) else {
          fail("sequence expected")
        }
        assert_true(
          @relation.sequence_obligations(op).contains(AtomicMatchLimits),
        )
        assert_true(@pipeline.row_count(p, Step(step)) is None)
      }
    }
  }
}

///|
test "sequence limit association rejects scope policy enforcement and unsupported source substitution" {
  let p = pipeline(false, "allow", "")
  let selected = policy(false)
  for
    (mode, expected) in [
      (1, @capacity_sequence_limit.CandidateScopeMismatch(OutputRows, 0)),
      (2, WrongEnforcement(OutputRows)),
      (3, SubjectMismatch(OutputRows)),
      (5, CandidateScopeMismatch(MatchesPerKey, 0)),
    ] {
    assert_eq(
      @capacity_sequence_limit.check_host_limits(
        p,
        0,
        fixtures(mode, 0),
        selected,
        0,
        1,
        max_work=10,
      ).unwrap_err(),
      expected,
    )
  }
  assert_true(
    @capacity_sequence_limit.check_host_limits(
      p,
      0,
      fixtures(6, 0),
      selected,
      0,
      1,
      max_work=10,
    )
    is Err(UnsupportedCandidate(OutputRows, _)),
  )
  let sources = fixtures(0, 0)
  assert_true(
    @capacity_sequence_limit.check_host_limits(
      p,
      0,
      sources,
      selected,
      -1,
      1,
      max_work=10,
    )
    is Err(MissingLimit(MatchesPerKey)),
  )
  assert_true(
    @capacity_sequence_limit.check_host_limits(
      p,
      0,
      sources,
      selected,
      0,
      2,
      max_work=10,
    )
    is Err(MissingLimit(OutputRows)),
  )
  assert_true(
    @capacity_sequence_limit.check_host_limits(
      p,
      -1,
      sources,
      selected,
      0,
      1,
      max_work=10,
    )
    is Err(InvalidStep),
  )
  assert_true(
    @capacity_sequence_limit.check_host_limits(
      p,
      0,
      sources,
      selected,
      0,
      1,
      max_work=-1,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    @capacity_sequence_limit.check_host_limits(
      pipeline(true, "allow", ""),
      0,
      sources,
      selected,
      0,
      1,
      max_work=10,
    )
    is Err(WrongOperation),
  )
  for
    (field, scope) in [
      ("max_matches_per_key", @capacity_sequence_limit.MatchesPerKey),
      ("max_output_rows", OutputRows),
    ] {
    for value in [1, 7, 100] {
      // A tighter/equal Host ceiling never allows dropping the author's guard.
      let guarded = pipeline(
        false,
        "allow",
        ",\"" + field + "\":" + value.to_string(),
      )
      assert_eq(
        @capacity_sequence_limit.check_host_limits(
          guarded,
          0,
          sources,
          selected,
          0,
          1,
          max_work=10,
        ).unwrap_err(),
        UnresolvedAuthorSource(scope),
      )
    }
  }
}
