///|
fn public_rejected(
  value : @program_check.CheckOutcome,
) -> @program_check.CheckDiagnostic raise {
  match value {
    Rejected(diagnostic) => diagnostic
    _ => fail("expected rejection, not success or an external request")
  }
}

///|
test "unsupported declarations retain their authored source without wrapper traversal" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text.replace(
    old="\"params\":",
    new="\"bindings\":{\"b\":{\"type\":\"string\"}},\"params\":",
  )
  let diagnostic = public_rejected(
    @program_check.check_document(
      text,
      environment,
      None,
      limits,
      format=Json,
      source_path="declarations.actql",
    ),
  )
  assert_eq(@program_check.diagnostic_origin(diagnostic), Some(ProgramDocument))
  let location = @program_check.diagnostic_location(diagnostic).unwrap()
  assert_eq(
    @program_check.diagnostic_location_path(location),
    Some([@source.Key("bindings")]),
  )
  assert_eq(
    @program_check.diagnostic_location_source_path(location),
    "declarations.actql",
  )
  assert_true(
    @program_check.diagnostic_location_position(location) is Source(span) &&
    span.start_byte > 0,
  )
}

///|
test "public diagnostic locations distinguish malformed input and check configuration" {
  let (_, _, environment, _, limits) = public_input_fixture()
  let diagnostic = public_rejected(
    @program_check.check_document(
      "{",
      environment,
      None,
      limits,
      format=Json,
      source_path="broken.actql",
    ),
  )
  assert_eq(@program_check.diagnostic_origin(diagnostic), Some(ProgramDocument))
  let location = @program_check.diagnostic_location(diagnostic).unwrap()
  assert_eq(
    @program_check.diagnostic_location_source_path(location),
    "broken.actql",
  )
  assert_true(
    @program_check.diagnostic_location_position(location) is Source(span) &&
    span.start_byte == 1,
  )
  assert_eq(@program_check.diagnostic_alternative_count(diagnostic), 0)
  let invalid = public_rejected(
    @program_check.check_document(
      "{",
      environment,
      None,
      { ..limits, compilation: { ..limits.compilation, work: -1, }, },
      format=Json,
      source_path="not-parsed.actql",
    ),
  )
  assert_eq(@program_check.diagnostic_origin(invalid), Some(CheckConfiguration))
  assert_true(@program_check.diagnostic_location(invalid) is None)
  assert_true(@program_check.diagnostic_cause(invalid) is InvalidLimits)
}

///|
test "auto format diagnostics retain both alternatives without selecting a primary" {
  let (_, _, environment, _, limits) = public_input_fixture()
  let diagnostic = public_rejected(
    @program_check.check_document(
      "{",
      environment,
      None,
      limits,
      source_path="auto.actql",
    ),
  )
  assert_eq(@program_check.diagnostic_origin(diagnostic), Some(ProgramDocument))
  assert_true(@program_check.diagnostic_location(diagnostic) is None)
  assert_eq(@program_check.diagnostic_alternative_count(diagnostic), 2)
  for (i, format) in [(0, @syntax.Json), (1, @syntax.Yaml)] {
    let (actual, location) = @program_check.diagnostic_alternative_at(
      diagnostic, i,
    ).unwrap()
    assert_eq(actual, format)
    assert_eq(
      @program_check.diagnostic_location_source_path(location),
      "auto.actql",
    )
  }
  assert_true(@program_check.diagnostic_alternative_at(diagnostic, -1) is None)
  assert_true(@program_check.diagnostic_alternative_at(diagnostic, 2) is None)
}

///|
test "structural diagnostic paths are caller-owned and retention limits have no invented span" {
  let (text, parsed, environment, _, limits) = public_input_fixture()
  let diagnostic = public_rejected(
    @program_check.check_document(
      text.replace(old="actql/0.1", new="actql/9.9"),
      environment,
      None,
      limits,
      format=Json,
      source_path="wrong.actql",
    ),
  )
  let location = @program_check.diagnostic_location(diagnostic).unwrap()
  let path = @program_check.diagnostic_location_path(location).unwrap()
  assert_eq(path, [@source.Key("version")])
  path[0] = @source.Key("changed")
  assert_eq(
    @program_check.diagnostic_location_path(location),
    Some([@source.Key("version")]),
  )
  let smaller = {
    ..limits,
    input: {
      ..limits.input,
      source: { ..limits.input.source, max_input_bytes: 0, },
    },
  }
  let retained = public_rejected(
    @program_check.check_parsed(parsed, environment, None, smaller),
  )
  let location = @program_check.diagnostic_location(retained).unwrap()
  assert_eq(
    @program_check.diagnostic_location_source_path(location),
    "fixture.actql",
  )
  assert_eq(
    @program_check.diagnostic_location_position(location),
    @source.Unavailable,
  )
  assert_true(@program_check.diagnostic_location_path(location) is None)
}
