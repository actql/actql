///|
fn pattern_limits() -> PatternLimits {
  {
    max_work: 1000000,
    max_text_bytes: 1000000,
    max_ast_bytes: 1000000,
    max_ast_nodes: 100000,
    max_regex_depth: 100,
  }
}

///|
test "pattern closure preserves one owner and original mixed occurrence order" {
  let expression = "[regex_match(NULL, '(a)'), parse_timestamp(NULL, 'yyyy-MM-dd') IS NULL, regex_replace(NULL, '(b)', '$1') IS NULL]"
  let context = regex_fixture(expression)
  let checked = check_patterns(context, pattern_limits()).unwrap()
  assert_true(physical_equal(pattern_context(checked), context))
  assert_eq(pattern_count(checked), 9)
  assert_eq(expression_validation_count(context), 27)
  let mut next = 0
  for i in 0..<expression_validation_count(context) {
    let source = expression_validation_at(context, i).unwrap()
    if validation_site_requirement(source).obligation.kind
      is PatternValidation(op) {
      let result = pattern_at(checked, next).unwrap()
      let site = pattern_site(result)
      assert_true(physical_equal(validation_site_context(site), context))
      assert_eq(
        validation_site_location(site),
        validation_site_location(source),
      )
      assert_true(
        physical_equal(
          validation_site_requirement(site).expression,
          validation_site_requirement(source).expression,
        ),
      )
      match result {
        Timestamp(v) => {
          assert_eq(op, "parse_timestamp")
          assert_eq(@timestamp.value_width(timestamp_pattern_ast(v)), 10)
        }
        Regex(v) => {
          assert_true(op == "regex_match" || op == "regex_replace")
          assert_eq(@regex.capture_count(regex_pattern_ast(v)), 1)
        }
        Like(_) => fail("unexpected LIKE resolution")
      }
      next += 1
    }
  }
  assert_eq(next, pattern_count(checked))
  assert_true(pattern_at(checked, -1) is None)
  assert_true(pattern_at(checked, pattern_count(checked)) is None)
  let other = check_patterns(regex_fixture(expression), pattern_limits()).unwrap()
  assert_false(physical_equal(pattern_context(other), context))
}

///|
test "combined pattern budgets subtract shared context once and accumulate both AST families" {
  let context = regex_fixture(
    "[regex_match(NULL, 'é'), parse_timestamp(NULL, 'yyyy-MM-dd') IS NULL]",
  )
  let checked = check_patterns(context, pattern_limits()).unwrap()
  let used = pattern_usage(checked)
  let base = expression_validation_usage(context)
  let t = timestamp_pattern_usage(
    check_timestamp_patterns(context, timestamp_limits()).unwrap(),
  )
  let r = regex_pattern_usage(
    check_regex_patterns(context, regex_limits()).unwrap(),
  )
  assert_eq(
    used.work,
    t.work + (r.work - base.work) + 3 * expression_validation_count(context),
  )
  assert_eq(used.text_bytes, t.text_bytes + (r.text_bytes - base.text_bytes))
  assert_eq(used.ast_bytes, t.ast_bytes + r.ast_bytes)
  assert_eq(used.ast_nodes, t.ast_nodes + r.ast_nodes)
  let exact : PatternLimits = {
    max_work: used.work,
    max_text_bytes: used.text_bytes,
    max_ast_bytes: used.ast_bytes,
    max_ast_nodes: used.ast_nodes,
    max_regex_depth: 100,
  }
  assert_true(check_patterns(context, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_ast_bytes: used.ast_bytes - 1, },
      { ..exact, max_ast_nodes: used.ast_nodes - 1, },
    ] {
    assert_true(check_patterns(context, short) is Err(BudgetExceeded))
  }
  assert_true(
    check_patterns(context, { ..exact, max_ast_nodes: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "pattern closure is atomic and does not discharge unrelated obligation kinds" {
  let context = regex_fixture(
    "[parse_timestamp(NULL, 'yyyy-MM-dd') IS NULL, regex_replace(NULL, 'a', '$1') IS NULL]",
  )
  assert_true(
    check_patterns(context, pattern_limits()) is Err(Regex(UnknownCapture(5))),
  )
  let context = regex_fixture(
    "[regex_match(NULL, 'a'), parse_timestamp(NULL, 'bad') IS NULL]",
  )
  assert_true(
    check_patterns(context, pattern_limits())
    is Err(Timestamp(Pattern(5, @timestamp.InvalidComponent(0)))),
  )
  let context = regex_fixture("nfkc(NULL)", profile=capacity_profile(false))
  let checked = check_patterns(context, pattern_limits()).unwrap()
  assert_eq(pattern_count(checked), 0)
  assert_eq(expression_validation_count(pattern_context(checked)), 6)
  let context = regex_fixture(
    "regex_match(NULL, 'a')",
    profile=capacity_profile(false),
  )
  assert_true(
    check_patterns(context, pattern_limits()) is Err(Regex(MissingPolicy(2))),
  )
}
