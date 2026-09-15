///|
test "string aggregate requests distinguish payload capacity from row bounds" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text.replace(
    old="{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}",
    new="{\"derive\":{\"value\":\"id + $n\",\"label\":\"'a'\"}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"string_agg\",\"field\":\"label\",\"delimiter\":\",\",\"order_by\":[{\"id\":\"asc\"}]}}},\"as\":\"derived\"}",
  )
  let parsed = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="string.actql",
  ).unwrap()
  let requests = match
    @program_check.check_parsed(parsed, environment, None, limits) {
    NeedsInputs(requests) => requests
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
    Checked(_) =>
      fail("row or artifact capacity replaced string payload capacity")
  }
  let request = @program_check.input_request_at(requests, 0).unwrap()
  guard request.kind is AggregateStringByteLimit(source) else {
    fail("wrong missing string capacity request")
  }
  assert_true(
    physical_equal(
      @program_check.input_request_source(request).unwrap(),
      source,
    ),
  )
  assert_eq(@program_check.input_request_origin(request), ProgramDocument)
  assert_eq(
    @program_check.diagnostic_location_source_path(
      @program_check.diagnostic_location(
        @program_check.input_requests_diagnostic(requests),
      ).unwrap(),
    ),
    "string.actql",
  )
  let guarded = text.replace(
    old="\"delimiter\":\",\"",
    new="\"delimiter\":\",\",\"max_bytes\":10",
  )
  ignore(
    public_checked(
      @program_check.check_document(
        guarded,
        environment,
        None,
        limits,
        format=Json,
      ),
    ),
  )
  let invalid = text.replace(
    old="\"delimiter\":\",\"",
    new="\"delimiter\":\",\",\"max_bytes\":-1",
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
    @program_check.check_parsed(parsed, environment, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 0, },
    })
    is Rejected(_),
  )
}
