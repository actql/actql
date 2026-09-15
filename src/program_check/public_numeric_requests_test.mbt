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
