///|
test "numeric supplementation covers analytic pivot and window occurrences" {
  for kind in ["analytic", "pivot", "empty_pivot", "window"] {
    let (original, _, absent, _, limits) = public_input_fixture(
      generated=true,
      analytic_policy=kind == "analytic",
      calendar_profile=kind == "window",
    )
    let limits = {
      ..limits,
      compilation: {
        ..limits.compilation,
        structure: { ..limits.compilation.structure, steps: 10, },
      },
    }
    let (_, _, supplied, _, _) = public_input_fixture(
      generated=true,
      analytic_policy=kind == "analytic",
      calendar_profile=kind == "window",
      numeric_profile=Some(numeric_profile_fixture()),
    )
    let operation = match kind {
      "analytic" =>
        "{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"total\":{\"fn\":\"sum\",\"field\":\"value\"}}}},{\"select\":[\"id\",{\"value\":\"total\"}],\"as\":\"derived\"}"
      "window" =>
        "{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}},{\"window_group\":{\"by\":[],\"aggregates\":{\"total\":{\"fn\":\"avg\",\"field\":\"value\"}}}},{\"select\":[{\"id\":\"window_start\"},{\"value\":\"window_end\"}],\"as\":\"derived\"}"
      _ =>
        "{\"derive\":{\"kind\":{\"literal\":\"a\"}}},{\"pivot\":{\"index\":[\"id\"],\"column\":\"kind\",\"values\":" +
        (if kind == "empty_pivot" { "[]" } else { "[\"a\"]" }) +
        ",\"value\":\"value\",\"aggregate\":\"sum\",\"fill\":0}},{\"select\":[\"id\",{\"value\":\"" +
        (if kind == "empty_pivot" { "id" } else { "a" }) +
        "\"}],\"as\":\"derived\"}"
    }
    let text = original.replace(
      old="{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}",
      new="{\"derive\":{\"value\":\"id + $n\"}}," + operation,
    )
    let parsed = @syntax.parse(text, limits.input, format=Json).unwrap()
    let requests = match
      @program_check.check_parsed(parsed, absent, None, limits) {
      NeedsInputs(requests) => requests
      Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
      Checked(_) => fail("numeric material was not required: " + kind)
    }
    assert_true(
      @program_check.input_request_at(requests, 0).unwrap().kind
      is NumericReductionProfile(_),
    )
    let program = public_checked(
      @program_check.check_parsed(parsed, supplied, None, limits),
    )
    match kind {
      "analytic" =>
        assert_eq(
          @program_check.unit_analytic_numeric_slot_count(program, 0),
          Some(1),
        )
      "window" =>
        assert_eq(
          @program_check.unit_group_numeric_slot_count(program, 0),
          Some(1),
        )
      "empty_pivot" =>
        assert_eq(
          @program_check.unit_pivot_numeric_slot_count(program, 0),
          Some(0),
        )
      _ =>
        assert_eq(
          @program_check.unit_pivot_numeric_slot_count(program, 0),
          Some(1),
        )
    }
    assert_eq(
      @program_check.unit_analytic_numeric_slot_count(program, 1),
      Some(0),
    )
    assert_eq(@program_check.unit_pivot_numeric_slot_count(program, 1), Some(0))
  }
}

///|
test "numeric profile requests retain aggregate locations and recheck publicly" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text.replace(
    old="{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}",
    new="{\"derive\":{\"value\":\"id + $n\"}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"sum\",\"expr\":\"value\"}}},\"as\":\"derived\"}",
  )
  let program = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="numeric.actql",
  ).unwrap()
  guard @program_check.check_parsed(program, environment, None, limits)
    is NeedsInputs(requests) else {
    fail("expected numeric profile request")
  }
  assert_eq(@program_check.input_request_count(requests), 1)
  assert_eq(
    @program_check.diagnostic_category(
      @program_check.input_requests_diagnostic(requests),
    ),
    @program_check.MissingInput,
  )
  let request = @program_check.input_request_at(requests, 0).unwrap()
  guard request.kind is NumericReductionProfile(source) else {
    fail("wrong request kind")
  }
  assert_true(
    physical_equal(
      @program_check.input_request_source(request).unwrap(),
      source,
    ),
  )
  assert_eq(@program_check.input_request_origin(request), ProgramDocument)
  assert_eq(
    @program_check.input_request_path(request),
    @decode.cursor_path(source),
  )
  assert_eq(
    @program_check.diagnostic_location_source_path(
      @program_check.diagnostic_location(
        @program_check.input_requests_diagnostic(requests),
      ).unwrap(),
    ),
    "numeric.actql",
  )
  let (_, _, supplied, _, _) = public_input_fixture(
    numeric_profile=Some(numeric_profile_fixture()),
  )
  let checked = public_checked(
    @program_check.check_parsed(program, supplied, None, limits),
  )
  assert_eq(@program_check.unit_group_numeric_slot_count(checked, 0), Some(1))
  assert_eq(@program_check.unit_group_numeric_slot_count(checked, 1), Some(0))
  ignore(
    public_checked(
      @program_check.check_document(text, supplied, None, limits, format=Json),
    ),
  )
  assert_true(@program_check.input_request_at(requests, 1) is None)
  let invalid = text.replace(
    old="\"expr\":\"value\"",
    new="\"expr\":\"'not numeric'\"",
  )
  assert_true(
    @program_check.check_document(
      invalid,
      environment,
      None,
      limits,
      format=Json,
    )
    is Rejected(_),
  )
  assert_true(
    @numeric.admit(
      @utf8.encode("{}"),
      @numeric.cid(numeric_profile_fixture()),
      1000,
    )
    is Err(_),
  )
  assert_true(
    @program_check.check_parsed(program, environment, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 0, },
    })
    is Rejected(_),
  )
}
