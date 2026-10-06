///|
test "standard diagnostics retain expression scalar ranges and authored locations" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let source = text.replace(old="id + $n", new="'😀' + missing")
  for parsed in [false, true] {
    let diagnostic = public_rejected(
      if parsed {
        @program_check.check_parsed(
          @syntax.parse(
            source,
            limits.input,
            format=Json,
            source_path="operations.actql",
          ).unwrap(),
          environment,
          None,
          limits,
        )
      } else {
        @program_check.check_document(
          source,
          environment,
          None,
          limits,
          format=Json,
          source_path="operations.actql",
        )
      },
    )
    assert_eq(
      @program_check.diagnostic_origin(diagnostic),
      Some(ProgramDocument),
    )
    let location = @program_check.diagnostic_location(diagnostic).unwrap()
    assert_eq(
      @program_check.diagnostic_location_source_path(location),
      "operations.actql",
    )
    assert_eq(
      @program_check.diagnostic_location_path(location),
      Some([
        @source.Key("stages"),
        @source.Index(0),
        @source.Key("steps"),
        @source.Index(0),
        @source.Key("derive"),
        @source.Key("value"),
      ]),
    )
    let range = @program_check.diagnostic_expression_range(diagnostic).unwrap()
    // The non-BMP scalar occupies one position inside the decoded expression;
    // these offsets are neither UTF-16 units nor bytes in the JSON document.
    assert_eq((range.start, range.end), (6, 13))
    assert_true(
      @program_check.diagnostic_location_position(location) is Source(span) &&
      span.start_byte > range.end,
    )
  }
}

///|
test "standard Result diagnostics retain the offending field without an expression range" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let diagnostic = public_rejected(
    @program_check.check_document(
      text.replace(
        old="\"fields\":[\"id\",\"value\"]",
        new="\"fields\":[\"id\",\"absent\"]",
      ),
      environment,
      None,
      limits,
      format=Json,
      source_path="results.actql",
    ),
  )
  assert_eq(@program_check.diagnostic_origin(diagnostic), Some(ProgramDocument))
  let location = @program_check.diagnostic_location(diagnostic).unwrap()
  assert_eq(
    @program_check.diagnostic_location_path(location),
    Some([
      @source.Key("stages"),
      @source.Index(0),
      @source.Key("results"),
      @source.Key("out"),
      @source.Key("fields"),
      @source.Index(1),
    ]),
  )
  assert_true(@program_check.diagnostic_expression_range(diagnostic) is None)
  let path = @program_check.diagnostic_location_path(location).unwrap()
  path[0] = @source.Key("changed")
  assert_eq(
    @program_check.diagnostic_location_path(location).unwrap()[0],
    @source.Key("stages"),
  )
}

///|
test "expression type rejection retains the existing required domain and classification" {
  let (text, _, environment, _, limits) = public_input_fixture()
  for
    (expression, expected) in [
      ("sqrt('private-value') + $n", "number"),
      ("if(1, id + $n, 0)", "boolean"),
      ("to_number(lower(1)) + $n", "string"),
    ] {
    let source = text.replace(old="id + $n", new=expression)
    let diagnostic = public_rejected(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    assert_eq(@program_check.diagnostic_category(diagnostic), InvalidInput)
    guard @program_check.diagnostic_cause(diagnostic)
      is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
      raise @program_check.diagnostic_cause(diagnostic)
    }
    assert_true(
      issue.kind is Operation(Expression(TypeMismatch(actual))) &&
      actual == expected,
    )
  }
}
