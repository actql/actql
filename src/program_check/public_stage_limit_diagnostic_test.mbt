///|
test "Stage admission limits have the same category through document and parsed entries" {
  let (text, parsed, environment, _, limits) = public_input_fixture()
  let smaller = { ..limits, input: { ..limits.input, max_stages: 1, }, }
  let retained = public_rejected(
    @program_check.check_parsed(parsed, environment, None, smaller),
  )
  assert_eq(
    @program_check.diagnostic_category(retained),
    @program_check.CompileLimit,
  )
  assert_true(
    @program_check.diagnostic_cause(retained)
    is Program(RetentionLimit(Stages, ..)),
  )
  let retained_location = @program_check.diagnostic_location(retained).unwrap()
  assert_true(
    @program_check.diagnostic_location_path(retained_location) is None,
  )
  assert_eq(
    @program_check.diagnostic_location_position(retained_location),
    @source.Unavailable,
  )
  let baseline = public_checked(
    @program_check.check_parsed(parsed, environment, None, limits),
  )
  for format in [@syntax.Json, @syntax.Auto] {
    let diagnostic = public_rejected(
      @program_check.check_document(text, environment, None, smaller, format~),
    )
    assert_eq(
      @program_check.diagnostic_category(diagnostic),
      @program_check.CompileLimit,
    )
    assert_true(
      @program_check.diagnostic_cause(diagnostic)
      is Program(Structure(StageLimit, ..)),
    )
    let location = @program_check.diagnostic_location(diagnostic).unwrap()
    assert_eq(
      @program_check.diagnostic_location_path(location),
      Some([@source.Key("stages")]),
    )
    assert_true(
      @program_check.diagnostic_location_position(location) is Source(_),
    )
    let checked = public_checked(
      @program_check.check_document(text, environment, None, limits, format~),
    )
    for unit in 0..<2 {
      assert_eq(
        @program_check.unit_definition_cid(checked, unit),
        @program_check.unit_definition_cid(baseline, unit),
      )
    }
  }
  let invalid = { ..limits, input: { ..limits.input, max_stages: -1, }, }
  for
    outcome in [
      @program_check.check_document(
        text,
        environment,
        None,
        invalid,
        format=Json,
      ),
      @program_check.check_document(
        text,
        environment,
        None,
        invalid,
        format=Auto,
      ),
      @program_check.check_parsed(parsed, environment, None, invalid),
    ] {
    assert_eq(
      @program_check.diagnostic_category(public_rejected(outcome)),
      @program_check.InvalidConfiguration,
    )
  }
}

///|
test "invalid Stage structure is not classified as a compile limit" {
  let (text, _, environment, _, limits) = public_input_fixture()
  for format in [@syntax.Json, @syntax.Auto] {
    for
      source in [
        "{\"version\":\"actql/0.1\",\"id\":\"empty\",\"stages\":[],\"results\":{}}",
        text.replace(old="\"id\":\"consumer\"", new="\"id\":\"producer\""),
      ] {
      let diagnostic = public_rejected(
        @program_check.check_document(
          source,
          environment,
          None,
          limits,
          format~,
        ),
      )
      assert_eq(
        @program_check.diagnostic_category(diagnostic),
        @program_check.InvalidInput,
      )
      assert_true(
        @program_check.diagnostic_cause(diagnostic)
        is Program(Structure(EmptyStages | DuplicateStage(_), ..)),
      )
    }
  }
}
