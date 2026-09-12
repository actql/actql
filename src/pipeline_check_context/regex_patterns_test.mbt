///|
fn regex_limits() -> RegexPatternLimits {
  {
    max_work: 1000000,
    max_text_bytes: 1000000,
    max_ast_bytes: 1000000,
    max_ast_nodes: 100000,
    max_pattern_depth: 100,
  }
}

///|
fn regex_fixture(
  expression : String,
  capacity_policy? : @policy.Policy = policy(),
  steps? : String? = None,
  second_steps? : String? = None,
  accepted? : Bool = false,
  parameters? : String = "{\"p\":{\"type\":\"string\",\"default\":\"(a)\"},\"c\":{\"type\":\"number\",\"default\":1},\"r\":{\"type\":\"string\",\"default\":\"$1$$\"}}",
  supplied? : @decode.Cursor? = None,
  profile? : String = validation_profile(
    valid_text_policy().replace(
      old="\"max_pattern_bytes\":1",
      new="\"max_pattern_bytes\":100",
    ),
  ),
) -> ExpressionValidationContext {
  timestamp_fixture(
    expression,
    capacity_policy~,
    parameters~,
    supplied~,
    profile~,
    steps~,
    second_steps~,
    accepted~,
  )
}

///|
test "regex static options belong to the exact bindings and unused expression visits" {
  let expression = "if(TRUE, '', regex_replace(NULL, $p, $r, 'sm'))"
  let context = regex_fixture(
    expression,
    parameters="{\"r\":{\"type\":\"string\",\"default\":\"$9\"},\"p\":{\"type\":\"string\",\"default\":\"invalid(\"},\"a\":{\"type\":\"number\",\"default\":1}}",
    supplied=Some(cursor("{\"p\":\"(a)\",\"r\":\"$1$$\"}")),
  )
  let checked = check_regex_patterns(context, regex_limits()).unwrap()
  assert_true(physical_equal(regex_pattern_context(checked), context))
  assert_eq(regex_pattern_count(checked), 3)
  assert_eq(expression_validation_count(context), 9)
  for i in 0..<3 {
    let r = regex_pattern_at(checked, i).unwrap()
    let site = regex_pattern_site(r)
    assert_true(physical_equal(validation_site_context(site), context))
    let requirement = validation_site_requirement(site)
    assert_eq(
      requirement.obligation.kind,
      @typing.PatternValidation("regex_replace"),
    )
    assert_eq(requirement.visit, if i == 2 { 1 } else { 0 })
    assert_eq(validation_site_location(site).0, if i == 0 { 0 } else { 1 })
    assert_eq(@regex.capture_count(regex_pattern_ast(r)), 1)
    assert_eq(regex_pattern_flags(r), Some("sm"))
    let pattern_parameter = regex_pattern_parameter(r).unwrap()
    let option_parameter = regex_option_parameter(r).unwrap()
    assert_eq(pattern_parameter.name, "p")
    assert_eq(option_parameter.name, "r")
    assert_true(pattern_parameter.origin is @parameter.Supplied)
    assert_true(option_parameter.origin is @parameter.Supplied)
    let values = @references.bound_values(
      validation_site_parameters(site).bound.unwrap(),
    )
    assert_true(
      physical_equal(
        pattern_parameter.value,
        @parameter.bound_value_at(values, 1).unwrap().value,
      ),
    )
    assert_true(
      physical_equal(
        option_parameter.value,
        @parameter.bound_value_at(values, 2).unwrap().value,
      ),
    )
    assert_true(
      physical_equal(
        regex_pattern_policy(r),
        expression_validation_text_time(context).unwrap(),
      ),
    )
    match regex_pattern_operation(r) {
      Replace(ast) => {
        assert_eq(@replacement.stats(ast).max_capture_index, 1)
        assert_eq(@replacement.stats(ast).literal_utf8_bytes, 1)
      }
      _ => fail("expected checked replacement")
    }
  }
  assert_true(regex_pattern_at(checked, -1) is None)
  assert_true(regex_pattern_at(checked, 3) is None)
  let other = regex_fixture(expression)
  let other = check_regex_patterns(other, regex_limits()).unwrap()
  assert_eq(
    @regex.cid(regex_pattern_ast(regex_pattern_at(checked, 0).unwrap())),
    @regex.cid(regex_pattern_ast(regex_pattern_at(other, 0).unwrap())),
  )
  assert_false(physical_equal(regex_pattern_context(other), context))
}

///|
test "regex captures include zero and reject invalid bound static options before demand" {
  let expression = "regex_extract(NULL, $p, $c)"
  for capture in ["0", "1"] {
    let checked = check_regex_patterns(
      regex_fixture(
        expression,
        supplied=Some(cursor("{\"c\":" + capture + "}")),
      ),
      regex_limits(),
    ).unwrap()
    assert_true(
      regex_pattern_operation(regex_pattern_at(checked, 0).unwrap())
      is Extract(_),
    )
  }
  for capture in ["-1", "0.5"] {
    assert_true(
      check_regex_patterns(
        regex_fixture(
          expression,
          supplied=Some(cursor("{\"c\":" + capture + "}")),
        ),
        regex_limits(),
      )
      is Err(InvalidArgument(2, "capture")),
    )
  }
  for capture in ["2", "1e100"] {
    assert_true(
      check_regex_patterns(
        regex_fixture(
          expression,
          supplied=Some(cursor("{\"c\":" + capture + "}")),
        ),
        regex_limits(),
      )
      is Err(UnknownCapture(2)),
    )
  }
  let nulls = "{\"p\":{\"type\":\"string\",\"default\":\"(a)\"},\"c\":{\"type\":\"number\",\"nullable\":true,\"default\":null},\"r\":{\"type\":\"string\",\"nullable\":true,\"default\":null}}"
  assert_true(
    check_regex_patterns(
      regex_fixture(expression, parameters=nulls),
      regex_limits(),
    )
    is Err(InvalidArgument(2, "capture")),
  )
  assert_true(
    check_regex_patterns(
      regex_fixture("regex_replace(NULL, $p, $r)", parameters=nulls),
      regex_limits(),
    )
    is Err(InvalidArgument(2, "replacement")),
  )
  assert_true(
    check_regex_patterns(
      regex_fixture(
        "regex_match(NULL, $p)",
        parameters="{\"p\":{\"type\":\"string\",\"nullable\":true,\"default\":null}}",
      ),
      regex_limits(),
    )
    is Err(InvalidArgument(2, "pattern")),
  )
  for replacement in ["$2", "$99"] {
    assert_true(
      check_regex_patterns(
        regex_fixture(
          "if(TRUE, '', regex_replace(NULL, $p, $r))",
          supplied=Some(cursor("{\"r\":\"" + replacement + "\"}")),
        ),
        regex_limits(),
      )
      is Err(UnknownCapture(2)),
    )
  }
  assert_true(
    check_regex_patterns(
      regex_fixture("regex_replace(NULL, $p, '$0')"),
      regex_limits(),
    )
    is Err(Replacement(2, @replacement.InvalidReplacement(0))),
  )
  assert_true(
    check_regex_patterns(
      regex_fixture("regex_match(NULL, '(a?)+')"),
      regex_limits(),
    )
    is Err(Pattern(2, @regex.NullableRepeat(4))),
  )
}

///|
test "regex policy measures UTF-8 and preserves flags without inventing profile or envelope proof" {
  let expression = "regex_match(NULL, 'é')"
  assert_true(
    check_regex_patterns(
      regex_fixture(expression, profile=capacity_profile(false)),
      regex_limits(),
    )
    is Err(MissingPolicy(2)),
  )
  assert_true(
    check_regex_patterns(
      regex_fixture(expression, profile=validation_profile(valid_text_policy())),
      regex_limits(),
    )
    is Err(PatternCeiling(2)),
  )
  let exact_policy = validation_profile(
    valid_text_policy().replace(
      old="\"max_pattern_bytes\":1",
      new="\"max_pattern_bytes\":2",
    ),
  )
  let checked = check_regex_patterns(
    regex_fixture(expression, profile=exact_policy),
    regex_limits(),
  ).unwrap()
  assert_eq(regex_pattern_count(checked), 3)
  for
    (suffix, expected) in [
      ("", None),
      (", ''", Some("")),
      (", 'ms'", Some("ms")),
      (", 'sm'", Some("sm")),
    ] {
    let checked = check_regex_patterns(
      regex_fixture("regex_match(NULL, 'a'" + suffix + ")"),
      regex_limits(),
    ).unwrap()
    let r = regex_pattern_at(checked, 0).unwrap()
    assert_eq(regex_pattern_flags(r), expected)
    assert_true(regex_pattern_operation(r) is Match)
    assert_true(regex_pattern_parameter(r) is None)
    assert_true(regex_option_parameter(r) is None)
  }
  let context = regex_fixture("parse_timestamp(NULL, 'yyyy-MM-dd')")
  let checked = check_regex_patterns(context, regex_limits()).unwrap()
  assert_eq(regex_pattern_count(checked), 0)
  assert_eq(expression_validation_count(regex_pattern_context(checked)), 9)
}

///|
test "regex source and AST budgets accumulate and late failures expose no prefix result" {
  let context = regex_fixture(
    "[regex_extract(NULL, '(a)', 0), regex_replace(NULL, '(b)', '$1')]",
  )
  let checked = check_regex_patterns(context, regex_limits()).unwrap()
  assert_eq(regex_pattern_count(checked), 6)
  let used = regex_pattern_usage(checked)
  let before = expression_validation_usage(context)
  assert_eq(used.text_bytes, before.text_bytes + 24)
  let first = regex_pattern_at(checked, 0).unwrap()
  let (_, bytes, nodes) = @regex.usage(regex_pattern_ast(first))
  let second = regex_pattern_at(checked, 1).unwrap()
  let (rbytes, rnodes) = match regex_pattern_operation(second) {
    Replace(r) => {
      let (_, bytes, nodes) = @replacement.usage(r)
      (bytes, nodes)
    }
    _ => fail("replacement missing")
  }
  assert_eq(used.ast_bytes, 6 * bytes + 3 * rbytes)
  assert_eq(used.ast_nodes, 6 * nodes + 3 * rnodes)
  let exact : RegexPatternLimits = {
    max_work: used.work,
    max_text_bytes: used.text_bytes,
    max_ast_bytes: used.ast_bytes,
    max_ast_nodes: used.ast_nodes,
    max_pattern_depth: 100,
  }
  assert_true(check_regex_patterns(context, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_ast_bytes: used.ast_bytes - 1, },
      { ..exact, max_ast_nodes: used.ast_nodes - 1, },
      { ..exact, max_pattern_depth: 0, },
    ] {
    assert_true(check_regex_patterns(context, short) is Err(BudgetExceeded))
  }
  for
    invalid in [
      { ..exact, max_work: -1, },
      { ..exact, max_text_bytes: -1, },
      { ..exact, max_ast_bytes: -1, },
      { ..exact, max_ast_nodes: -1, },
      { ..exact, max_pattern_depth: -1, },
    ] {
    assert_true(check_regex_patterns(context, invalid) is Err(InvalidLimits))
  }
  assert_true(
    check_regex_patterns(
      regex_fixture("[regex_match(NULL, 'a'), regex_match(NULL, '(')]"),
      regex_limits(),
    )
    is Err(Pattern(5, @regex.InvalidSyntax(1))),
  )
}
