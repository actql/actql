///|
test "sequence guard lookup keeps original indices without scanning other steps" {
  let step =
    #|{"sequence":{"by":[],"id":"id","time":"id","pattern":[{"as":"a","where":"TRUE"},{"as":"b","where":"TRUE"}],"within":1,"overlap":"allow","contiguity":"adjacent","max_matches_per_key":1,"max_output_rows":2},"from":"rows"}
  let p = pipeline_text("[" + step + "," + step + "]")
  let guards = @pipeline.collect_author_guards(
    p,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  let bound = @pipeline.bind_author_guards(
    guards,
    None,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  for i in 0..<2 {
    let sources = fixtures(0, i)
    let selected = policy(false)
    let checked = @capacity_sequence_limit.check_bound_limits(
      p,
      i,
      sources,
      selected,
      0,
      1,
      bound,
      max_work=6,
    ).unwrap()
    assert_eq(
      @capacity_sequence_limit.guard_index(checked, MatchesPerKey),
      Some(i * 2),
    )
    assert_eq(
      @capacity_sequence_limit.guard_index(checked, OutputRows),
      Some(i * 2 + 1),
    )
    assert_eq(@capacity_sequence_limit.usage(checked), 6)
    assert_true(
      @capacity_sequence_limit.check_bound_limits(
        p,
        i,
        sources,
        selected,
        0,
        1,
        bound,
        max_work=5,
      )
      is Err(WorkLimit),
    )
  }
}

///|
test "bound sequence limits retain tighter equal and looser authored occurrences" {
  for (matches, output) in [(1, 2), (3, 7), (10, 20)] {
    let p = pipeline(
      false,
      "allow",
      ",\"max_matches_per_key\":" +
      matches.to_string() +
      ",\"max_output_rows\":" +
      output.to_string(),
    )
    let guards = @pipeline.collect_author_guards(
      p,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let bound = @pipeline.bind_author_guards(
      guards,
      None,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let sources = fixtures(0, 0)
    let selected = policy(false)
    let result = @capacity_sequence_limit.check_bound_limits(
      p,
      0,
      sources,
      selected,
      0,
      1,
      bound,
      max_work=6,
    ).unwrap()
    assert_eq(@capacity_sequence_limit.usage(result), 6)
    assert_true(
      physical_equal(
        @capacity_sequence_limit.bound_guards(result).unwrap(),
        bound,
      ),
    )
    for
      (scope, authored, host) in [
        (@capacity_sequence_limit.MatchesPerKey, matches, 3),
        (OutputRows, output, 7),
      ] {
      assert_eq(
        @capacity_sequence_limit.guard_value(result, scope),
        Some(authored.to_int64()),
      )
      assert_eq(
        @capacity_sequence_limit.effective_maximum(result, scope),
        Int::min(authored, host).to_int64(),
      )
      let index = @capacity_sequence_limit.guard_index(result, scope).unwrap()
      let occurrence = @pipeline.author_guard_at(guards, index).unwrap()
      assert_eq(@pipeline.author_guard_step(occurrence), 0)
      assert_true(
        physical_equal(@pipeline.author_guard_pipeline(occurrence), p),
      )
      assert_eq(
        @arithmetic.minimum_value(
          @wire.limit_minimum(
            @capacity_sequence_limit.host_limit(result, scope),
          ),
        ),
        host.to_int64(),
      )
    }
    assert_true(
      @capacity_sequence_limit.check_bound_limits(
        p,
        0,
        sources,
        selected,
        0,
        1,
        bound,
        max_work=5,
      )
      is Err(WorkLimit),
    )
    let foreign = pipeline(
      false,
      "allow",
      ",\"max_matches_per_key\":" +
      matches.to_string() +
      ",\"max_output_rows\":" +
      output.to_string(),
    )
    assert_true(
      @capacity_sequence_limit.check_bound_limits(
        foreign,
        0,
        sources,
        selected,
        0,
        1,
        bound,
        max_work=6,
      )
      is Err(ForeignGuardOwner),
    )
    assert_true(
      @capacity_sequence_limit.check_host_limits(
        p,
        0,
        sources,
        selected,
        0,
        1,
        max_work=6,
      )
      is Err(UnresolvedAuthorSource(_)),
    )
  }
}

///|
test "sequence guard selection keeps omitted scopes absent" {
  for guard_text in ["", ",\"max_matches_per_key\":1", ",\"max_output_rows\":2"] {
    let p = pipeline(false, "disallow", guard_text)
    let guards = @pipeline.collect_author_guards(
      p,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let bound = @pipeline.bind_author_guards(
      guards,
      None,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let checked = @capacity_sequence_limit.check_bound_limits(
      p,
      0,
      fixtures(0, 0),
      policy(false),
      0,
      1,
      bound,
      max_work=1000,
    ).unwrap()
    assert_eq(
      @capacity_sequence_limit.guard_value(checked, MatchesPerKey),
      if guard_text.contains("max_matches") {
        Some(1L)
      } else {
        None
      },
    )
    assert_eq(
      @capacity_sequence_limit.guard_value(checked, OutputRows),
      if guard_text.contains("max_output") {
        Some(2L)
      } else {
        None
      },
    )
  }
}

///|
fn guard_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
test "sequence collection rejects equal-valued but foreign Parameter bindings" {
  let declarations = @parameter.read_declarations(
    Some(guard_cursor("{\"n\":{\"type\":\"number\",\"default\":2}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 20, max_text_bytes: 4096, },
  ).unwrap()
  let p = pipeline_text(
    "[{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"a\",\"where\":\"TRUE\"},{\"as\":\"b\",\"where\":\"TRUE\"}],\"within\":1,\"overlap\":\"allow\",\"contiguity\":\"adjacent\",\"max_matches_per_key\":{\"$param\":\"n\"}}}]",
    parameters=Some(declarations),
  )
  let bind = fn() {
    guard @parameter.bind(declarations, None, {
        max_nodes: 100,
        max_depth: 20,
        max_text_bytes: 4096,
      }).unwrap()
      is @parameter.Ready(values) else {
      abort("fixture binding")
    }
    values
  }
  let values = bind()
  let guards = @pipeline.collect_author_guards(
    p,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  let bound = @pipeline.bind_author_guards(
    guards,
    Some(values),
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  let repeated = @pipeline.bind_author_guards(
    guards,
    Some(values),
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  let foreign = @pipeline.bind_author_guards(
    guards,
    Some(bind()),
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  let sources = fixtures(0, 0)
  let selected = policy(false)
  let limits = @capacity_sequence_limit.check_bound_limits(
    p,
    0,
    sources,
    selected,
    0,
    1,
    bound,
    max_work=1000,
  ).unwrap()
  assert_eq(
    @capacity_sequence_limit.effective_maximum(limits, MatchesPerKey),
    2L,
  )
  let apps = @capacity_sequence_limit.check_applications(
    p,
    sources,
    selected,
    [limits],
    max_work=1000,
  ).unwrap()
  assert_true(
    @capacity_sequence_limit.application_guard_bindings_match(apps, bound),
  )
  assert_true(
    @capacity_sequence_limit.application_guard_bindings_match(apps, repeated),
  )
  assert_false(
    @capacity_sequence_limit.application_guard_bindings_match(apps, foreign),
  )
}
