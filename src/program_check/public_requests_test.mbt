///|
fn request_values(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
      source_path="values.json",
    ).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
test "missing Parameter requests retain type location and exact admitted Program" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text.replace(old=",\"default\":1", new="")
  let program = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="requests.actql",
  ).unwrap()
  guard @program_check.check_parsed(program, environment, None, limits)
    is NeedsInputs(requests) else {
    fail("expected an input request")
  }
  assert_eq(@program_check.input_request_count(requests), 1)
  let request = @program_check.input_request_at(requests, 0).unwrap()
  assert_true(physical_equal(request.program, program))
  guard request.kind is ParameterValue(declaration) else {
    fail("expected Parameter")
  }
  assert_eq(declaration.name, "n")
  assert_true(declaration.parameter_type.contract.shape is Number)
  assert_false(@parameters.has_default(declaration))
  let source = @parameters.declaration_source(declaration)
  assert_eq(@decode.cursor_path(source), [
    @source.Key("params"),
    @source.Key("n"),
  ])
  assert_eq(@decode.cursor_span(source).source_path, "requests.actql")
  assert_true(@decode.cursor_span(source).start_byte > 0)
  guard @program_check.input_request_at(requests, 0).unwrap().kind
    is ParameterValue(again) else {
    fail("expected Parameter")
  }
  assert_true(physical_equal(again, declaration))
  assert_true(@program_check.input_request_at(requests, -1) is None)
  assert_true(@program_check.input_request_at(requests, 1) is None)
  assert_true(
    @program_check.check_document(
      text,
      environment,
      None,
      limits,
      format=Json,
      source_path="requests.actql",
    )
    is NeedsInputs(_),
  )
  // The response is ordinary untrusted supplied data, not a fulfillment flag.
  let supplied = Some(request_values("{\"n\":2}"))
  assert_true(
    @program_check.check_parsed(program, environment, supplied, limits)
    is Checked(_),
  )
  let changed = text.replace(
    old="\"n\":{\"type\":\"number\"}",
    new="\"n\":{\"type\":\"number\",\"minimum\":10}",
  )
  assert_true(
    @program_check.check_document(
      changed,
      environment,
      supplied,
      limits,
      format=Json,
    )
    is Rejected(_),
  )
  // Previous requests remain immutable; no resume state or partial success.
  assert_eq(@program_check.input_request_count(requests), 1)
}

///|
test "invalid inputs unsupported paths and exhausted work are not external requests" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text
    .replace(old=",\"default\":1", new="")
    .replace(old="\"params\":{", new="\"params\":{\"m\":{\"type\":\"number\"},")
  let limits = {
    ..limits,
    compilation: {
      ..limits.compilation,
      structure: { ..limits.compilation.structure, parameters: 2, },
    },
  }
  guard @program_check.check_document(
      text,
      environment,
      Some(request_values("{\"n\":2}")),
      limits,
      format=Json,
    )
    is NeedsInputs(missing) else {
    fail("valid supplied n must leave a request for m")
  }
  assert_eq(@program_check.input_request_count(missing), 1)
  guard @program_check.input_request_at(missing, 0).unwrap().kind
    is ParameterValue(m) else {
    fail("expected Parameter")
  }
  assert_eq(m.name, "m")
  let invalid = @program_check.check_document(
    text,
    environment,
    Some(request_values("{\"n\":\"bad\"}")),
    limits,
    format=Json,
  )
  guard invalid is Rejected(diagnostic) else {
    fail("invalid n was masked by missing m")
  }
  assert_true(
    @program_check.diagnostic_cause(diagnostic)
    is @program_check.LocalConstructionFailure::Source(_),
  )
  assert_true(
    @program_check.check_document(
      text,
      environment,
      None,
      { ..limits, compilation: { ..limits.compilation, work: 0, }, },
      format=Json,
    )
    is Rejected(_),
  )
  let unsupported = text.replace(
    old="\"version\":",
    new="\"bindings\":{},\"version\":",
  )
  assert_true(
    @program_check.check_document(
      unsupported,
      environment,
      None,
      limits,
      format=Json,
    )
    is Rejected(_),
  )
}
