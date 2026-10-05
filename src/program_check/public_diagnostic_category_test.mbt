///|
test "unused Parameter declarations retain the existing input rejection" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text.replace(old="id + $n", new="id + 1")
  let parsed = @syntax.parse(text, limits.input, format=Json).unwrap()
  for
    outcome in [
      @program_check.check_document(
        text,
        environment,
        None,
        limits,
        format=Json,
      ),
      @program_check.check_parsed(parsed, environment, None, limits),
    ] {
    let diagnostic = public_rejected(outcome)
    guard @program_check.diagnostic_cause(diagnostic)
      is @program_check.LocalConstructionFailure::Source(
        Identity(References(Usage(UnusedParameter(declaration))))
      ) else {
      raise @program_check.diagnostic_cause(diagnostic)
    }
    assert_eq(declaration.name, "n")
    assert_eq(@program_check.diagnostic_category(diagnostic), InvalidInput)
    // This classification does not invent a public input location.
    assert_true(@program_check.diagnostic_location(diagnostic) is None)
  }
}

///|
test "document and parsed diagnostics expose semantic categories without phase matching" {
  let (text, _, environment, _, limits) = public_input_fixture()
  for
    (source, expected) in [
      (
        text.replace(old="id + $n", new="missing + 1"),
        @program_check.InvalidInput,
      ),
      (
        text.replace(
          old="\"params\":",
          new="\"bindings\":{\"b\":{\"type\":\"string\"}},\"params\":",
        ),
        @program_check.UnsupportedImplementation,
      ),
      (
        text.replace(old="\"default\":1", new="\"default\":\"bad\""),
        @program_check.InvalidInput,
      ),
    ] {
    let parsed = @syntax.parse(
      source,
      limits.input,
      format=Json,
      source_path="category.actql",
    ).unwrap()
    let document = public_rejected(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
        source_path="category.actql",
      ),
    )
    let reused = public_rejected(
      @program_check.check_parsed(parsed, environment, None, limits),
    )
    assert_eq(@program_check.diagnostic_category(document), expected)
    assert_eq(@program_check.diagnostic_category(reused), expected)
    assert_eq(
      @program_check.diagnostic_origin(document),
      @program_check.diagnostic_origin(reused),
    )
    let a = @program_check.diagnostic_location(document).unwrap()
    let b = @program_check.diagnostic_location(reused).unwrap()
    assert_eq(
      @program_check.diagnostic_location_path(a),
      @program_check.diagnostic_location_path(b),
    )
    assert_eq(
      @program_check.diagnostic_location_position(a),
      @program_check.diagnostic_location_position(b),
    )
    assert_eq(
      @program_check.diagnostic_expression_range(document),
      @program_check.diagnostic_expression_range(reused),
    )
  }
}

///|
test "public diagnostics distinguish exhausted budgets invalid settings and missing inputs" {
  let (text, parsed, environment, _, limits) = public_input_fixture(
    generated=true,
  )
  for work in [-1, 0, 1, 10, 100] {
    let limits = { ..limits, compilation: { ..limits.compilation, work, }, }
    let expected = if work < 0 {
      @program_check.InvalidConfiguration
    } else {
      @program_check.CompileLimit
    }
    for
      outcome in [
        @program_check.check_document(
          text,
          environment,
          None,
          limits,
          format=Json,
        ),
        @program_check.check_parsed(parsed, environment, None, limits),
      ] {
      let diagnostic = public_rejected(outcome)
      assert_eq(
        @program_check.diagnostic_category(diagnostic),
        expected,
        msg="work=" + work.to_string(),
      )
    }
  }
  let text = text.replace(old="\"default\":1", new="\"nullable\":false")
  let parsed = @syntax.parse(text, limits.input, format=Json).unwrap()
  for
    outcome in [
      @program_check.check_document(
        text,
        environment,
        None,
        limits,
        format=Json,
      ),
      @program_check.check_parsed(parsed, environment, None, limits),
    ] {
    guard outcome is NeedsInputs(requests) else {
      fail("missing Parameter must remain a typed request")
    }
    assert_eq(
      @program_check.diagnostic_category(
        @program_check.input_requests_diagnostic(requests),
      ),
      @program_check.MissingInput,
    )
  }
}
