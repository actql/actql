///|
fn timestamp_limits() -> TimestampPatternLimits {
  {
    max_work: 1000000,
    max_text_bytes: 1000000,
    max_ast_bytes: 1000000,
    max_ast_nodes: 100000,
  }
}

///|
fn timestamp_fixture(
  expression : String,
  capacity_policy? : @policy.Policy = policy(),
  steps? : String? = None,
  second_steps? : String? = None,
  accepted? : Bool = false,
  parameters? : String = "{\"p\":{\"type\":\"string\",\"default\":\"yyyy-MM-dd\"}}",
  supplied? : @decode.Cursor? = None,
  profile? : String = validation_profile(
    valid_text_policy().replace(
      old="\"max_pattern_bytes\":1",
      new="\"max_pattern_bytes\":100",
    ),
  ),
) -> ExpressionValidationContext {
  let (context, capacity) = selected_fixture(
    false,
    capacity_policy~,
    profile~,
    expression~,
    steps~,
    second_steps~,
    accepted~,
    parameters~,
    supplied~,
  )
  let selected = bind_capacity_policy(
    context,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  prepare_expression_validation(selected, validation_limits()).unwrap()
}

///|
test "timestamp search follows UTF-16 order for unequal names" {
  let context = timestamp_fixture(
    "parse_timestamp(NULL, $count)",
    parameters="{\"count\":{\"type\":\"string\",\"default\":\"yyyy-MM-dd\"},\"n\":{\"type\":\"string\",\"default\":\"yyyy\"}}",
  )
  let checked = check_timestamp_patterns(context, timestamp_limits()).unwrap()
  assert_eq(
    timestamp_pattern_parameter(timestamp_pattern_at(checked, 0).unwrap()).unwrap().name,
    "count",
  )
}

///|
test "timestamp obligations resolve exact bindings in unused branches and repeated producers" {
  let expression = "if(TRUE, CAST(NULL AS TIMESTAMP), parse_timestamp(NULL, $p))"
  let context = timestamp_fixture(
    expression,
    parameters="{\"z\":{\"type\":\"string\",\"default\":\"z\"},\"p\":{\"type\":\"string\",\"default\":\"invalid\"},\"a\":{\"type\":\"string\",\"default\":\"a\"}}",
    supplied=Some(cursor("{\"p\":\"yyyy-MM-dd\"}")),
  )
  let checked = check_timestamp_patterns(context, timestamp_limits()).unwrap()
  assert_true(physical_equal(timestamp_pattern_context(checked), context))
  assert_eq(timestamp_pattern_count(checked), 3)
  assert_eq(expression_validation_count(context), 9)
  for i in 0..<3 {
    let resolution = timestamp_pattern_at(checked, i).unwrap()
    let site = timestamp_pattern_site(resolution)
    assert_true(physical_equal(validation_site_context(site), context))
    let requirement = validation_site_requirement(site)
    assert_eq(
      requirement.obligation.kind,
      @typing.PatternValidation("parse_timestamp"),
    )
    assert_eq(requirement.visit, if i == 2 { 1 } else { 0 })
    assert_eq(validation_site_location(site).0, if i == 0 { 0 } else { 1 })
    let pattern = timestamp_pattern_ast(resolution)
    assert_eq(@timestamp.mode(pattern), @timestamp.Parse)
    assert_eq(@timestamp.value_width(pattern), 10)
    let bound = timestamp_pattern_parameter(resolution).unwrap()
    assert_eq(bound.name, "p")
    assert_true(bound.origin is @parameter.Supplied)
    assert_true(bound.value.value is @value.Text("yyyy-MM-dd"))
    let values = @references.bound_values(
      validation_site_parameters(site).bound.unwrap(),
    )
    assert_true(
      physical_equal(
        bound.value,
        @parameter.bound_value_at(values, 1).unwrap().value,
      ),
    )
    assert_true(
      physical_equal(
        timestamp_pattern_policy(resolution),
        expression_validation_text_time(context).unwrap(),
      ),
    )
  }
  assert_true(timestamp_pattern_at(checked, -1) is None)
  assert_true(timestamp_pattern_at(checked, 3) is None)
  let other = check_timestamp_patterns(
    timestamp_fixture(expression),
    timestamp_limits(),
  ).unwrap()
  assert_eq(
    @timestamp.cid(
      timestamp_pattern_ast(timestamp_pattern_at(other, 0).unwrap()),
    ),
    @timestamp.cid(
      timestamp_pattern_ast(timestamp_pattern_at(checked, 0).unwrap()),
    ),
  )
  assert_false(
    physical_equal(
      validation_site_context(
        timestamp_pattern_site(timestamp_pattern_at(other, 0).unwrap()),
      ),
      context,
    ),
  )
}

///|
test "timestamp modes, literal arguments and cumulative budgets retain each occurrence" {
  let context = timestamp_fixture(
    "[parse_timestamp(NULL, 'yyyy-MM-dd'), try_timestamp(NULL, 'yyyy-MM-dd')]",
  )
  let checked = check_timestamp_patterns(context, timestamp_limits()).unwrap()
  assert_eq(timestamp_pattern_count(checked), 6)
  let before = expression_validation_usage(context)
  let used = timestamp_pattern_usage(checked)
  let ast = timestamp_pattern_ast(timestamp_pattern_at(checked, 0).unwrap())
  let (_, _, bytes, nodes) = @timestamp.usage(ast)
  assert_eq(used.text_bytes, before.text_bytes + 60)
  assert_eq(used.ast_bytes, bytes * 6)
  assert_eq(used.ast_nodes, nodes * 6)
  assert_eq(used.work, before.work + 18 + 6 + 60 + nodes * 6)
  for i in 0..<6 {
    assert_true(
      timestamp_pattern_parameter(timestamp_pattern_at(checked, i).unwrap())
      is None,
    )
  }
  let exact : TimestampPatternLimits = {
    max_work: used.work,
    max_text_bytes: used.text_bytes,
    max_ast_bytes: used.ast_bytes,
    max_ast_nodes: used.ast_nodes,
  }
  assert_true(check_timestamp_patterns(context, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_ast_bytes: used.ast_bytes - 1, },
      { ..exact, max_ast_nodes: used.ast_nodes - 1, },
    ] {
    assert_true(check_timestamp_patterns(context, short) is Err(BudgetExceeded))
  }
  for
    invalid in [
      { ..exact, max_work: -1, },
      { ..exact, max_text_bytes: -1, },
      { ..exact, max_ast_bytes: -1, },
      { ..exact, max_ast_nodes: -1, },
    ] {
    assert_true(
      check_timestamp_patterns(context, invalid) is Err(InvalidLimits),
    )
  }
  for pattern in ["yyyy", "--"] {
    let format = timestamp_fixture(
      "format_timestamp(CAST(NULL AS TIMESTAMP), '" + pattern + "')",
    )
    let checked = check_timestamp_patterns(format, timestamp_limits()).unwrap()
    assert_eq(
      @timestamp.mode(
        timestamp_pattern_ast(timestamp_pattern_at(checked, 0).unwrap()),
      ),
      @timestamp.Format,
    )
    assert_true(
      check_timestamp_patterns(
        timestamp_fixture("parse_timestamp(NULL, '" + pattern + "')"),
        timestamp_limits(),
      )
      is Err(Pattern(2, @timestamp.MissingDate)),
    )
  }
}

///|
test "timestamp resolution rejects missing policies, null patterns and late invalid patterns without repair" {
  let expression = "parse_timestamp(NULL, $p)"
  assert_true(
    check_timestamp_patterns(
      timestamp_fixture(expression, profile=capacity_profile(false)),
      timestamp_limits(),
    )
    is Err(MissingPolicy(2)),
  )
  assert_true(
    check_timestamp_patterns(
      timestamp_fixture(
        expression,
        profile=validation_profile(valid_text_policy()),
      ),
      timestamp_limits(),
    )
    is Err(PatternCeiling(2)),
  )
  let exact_policy = validation_profile(
    valid_text_policy().replace(
      old="\"max_pattern_bytes\":1",
      new="\"max_pattern_bytes\":10",
    ),
  )
  assert_true(
    check_timestamp_patterns(
      timestamp_fixture(expression, profile=exact_policy),
      timestamp_limits(),
    )
    is Ok(_),
  )
  assert_true(
    check_timestamp_patterns(
      timestamp_fixture(
        expression,
        parameters="{\"p\":{\"type\":\"string\",\"nullable\":true,\"default\":null}}",
      ),
      timestamp_limits(),
    )
    is Err(InvalidPatternValue(2)),
  )
  assert_true(
    check_timestamp_patterns(
      timestamp_fixture(expression, supplied=Some(cursor("{\"p\":\"$q\"}"))),
      timestamp_limits(),
    )
    is Err(Pattern(2, @timestamp.InvalidComponent(0))),
  )
  assert_true(
    check_timestamp_patterns(
      timestamp_fixture(
        "[parse_timestamp(NULL, 'yyyy-MM-dd'), try_timestamp(NULL, 'bad')]",
      ),
      timestamp_limits(),
    )
    is Err(Pattern(5, @timestamp.InvalidComponent(0))),
  )
  // No timestamp obligation: regex and profile/envelope work remains pending.
  let context = prepare_expression_validation(
    validation_fixture(capacity_profile(false), true),
    validation_limits(),
  ).unwrap()
  let checked = check_timestamp_patterns(context, timestamp_limits()).unwrap()
  assert_eq(timestamp_pattern_count(checked), 0)
  assert_eq(expression_validation_count(timestamp_pattern_context(checked)), 9)
}
