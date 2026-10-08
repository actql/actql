///|
test "invalid source-free UNNEST inputs are not implementation limits" {
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(unnest_parameter_path_declarations()),
  }
  for
    (text, expected) in [
      (
        "SELECT element.* FROM UNNEST(@missing.nested.items) element",
        @typing.UnknownParameter("missing"),
      ),
      (
        "SELECT element.* FROM UNNEST(@payload.nested.missing) element",
        @typing.UnknownField("missing"),
      ),
    ] {
    match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      ) {
      Err(ExpressionTyping(issue)) => assert_eq(issue.kind, expected, msg=text)
      _ => fail("the common typing cause must survive: " + text)
    }
  }
}

///|
test "UNNEST scope probes retain the undeclared parameter's authored location" {
  let text = "SELECT element.* FROM UNNEST(@missing.nested.items) element"
  let issue = match
    compile(
      @query.parse_query(text, syntax_limits(), source_path="submitted.sql").unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Err(ExpressionTyping(issue)) => issue
    _ => fail("expected the common undeclared-parameter issue")
  }
  assert_eq(issue.kind, @typing.UnknownParameter("missing"))
  let span = @wire.cursor_span(issue.location.source)
  assert_eq(span.source_path, "submitted.sql")
  assert_eq(span.start_byte, 29)
  assert_eq(span.end_byte, 37)
  assert_true(issue.location.range is None)
}

///|
test "known non-ARRAY UNNEST input retains an authored argument violation" {
  let text = "SELECT * FROM UNNEST(1) element"
  assert_true(
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.InvalidArguments, origin: Some(_), })
    ),
  )
}
