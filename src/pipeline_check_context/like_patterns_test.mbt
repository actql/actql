///|
test "LIKE closure resolves literal and bound patterns without a text-time policy" {
  let context = regex_fixture(
    "[NULL LIKE 'a%', NULL LIKE $p, NULL LIKE '\\😀_']",
    parameters="{\"p\":{\"type\":\"string\",\"default\":\"bad\\\\\"}}",
    supplied=Some(cursor("{\"p\":\"é_%\"}")),
    profile=capacity_profile(false),
  )
  let checked = check_patterns(context, pattern_limits()).unwrap()
  assert_true(physical_equal(pattern_context(checked), context))
  assert_eq(pattern_count(checked), 9)
  assert_eq(expression_validation_count(context), 9)
  for i in 0..<9 {
    let v = match pattern_at(checked, i).unwrap() {
      Like(v) => v
      _ => fail("expected LIKE resolution")
    }
    assert_true(
      physical_equal(validation_site_context(like_pattern_site(v)), context),
    )
    assert_eq(like_pattern_source(v), ["a%", "é_%", "\\😀_"][i % 3])
    if i % 3 == 1 {
      let parameter = like_pattern_parameter(v).unwrap()
      assert_eq(parameter.name, "p")
      let bound = @references.bound_values(
        validation_site_parameters(like_pattern_site(v)).bound.unwrap(),
      )
      assert_true(
        physical_equal(
          parameter.value,
          @parameter.bound_value_at(bound, 0).unwrap().value,
        ),
      )
    } else {
      assert_true(like_pattern_parameter(v) is None)
    }
  }
}

///|
test "LIKE validates escape parity including unused branches and nullable bindings" {
  for source in ["", "%_%", "\\%", "\\_", "\\q", "\\\\", "\\😀", "a\n%"] {
    let context = regex_fixture(
      "NULL LIKE $p",
      supplied=Some(cursor("{\"p\":" + source.to_json().stringify() + "}")),
      profile=capacity_profile(false),
    )
    assert_true(check_patterns(context, pattern_limits()) is Ok(_))
  }
  for (source, offset) in [("\\", 0), ("a\\", 1), ("\\\\\\", 2), ("😀\\", 2)] {
    let context = regex_fixture(
      "if(TRUE, TRUE, NULL LIKE $p)",
      supplied=Some(cursor("{\"p\":" + source.to_json().stringify() + "}")),
    )
    match check_patterns(context, pattern_limits()) {
      Err(Like(TrailingEscape(site, actual))) => {
        assert_eq(site, 0)
        assert_eq(actual, offset)
      }
      _ => fail("expected trailing escape")
    }
  }
  let context = regex_fixture(
    "NULL LIKE $p",
    parameters="{\"p\":{\"type\":\"string\",\"nullable\":true,\"default\":null}}",
  )
  assert_true(
    check_patterns(context, pattern_limits())
    is Err(Like(InvalidPatternValue(0))),
  )
  let context = regex_fixture("NULL LIKE '\\'")
  assert_true(
    check_patterns(context, pattern_limits()) is Err(Like(TrailingEscape(0, 0))),
  )
  // LIKE is not subject to the text-time max_pattern_bytes ceiling of one.
  let context = regex_fixture(
    "NULL LIKE 'é%_%'",
    profile=validation_profile(valid_text_policy()),
  )
  assert_true(
    check_patterns(context, {
      ..pattern_limits(),
      max_ast_bytes: 0,
      max_ast_nodes: 0,
      max_regex_depth: 0,
    })
    is Ok(_),
  )
  for n in 0..<66 {
    let context = regex_fixture(
      "NULL LIKE $p",
      supplied=Some(
        cursor("{\"p\":" + "\\".repeat(n).to_json().stringify() + "}"),
      ),
    )
    assert_eq(check_patterns(context, pattern_limits()) is Ok(_), n % 2 == 0)
  }
}

///|
test "LIKE participates in aggregate budgets and mixed pattern ordering" {
  let context = regex_fixture(
    "[regex_match(NULL, 'a'), NULL LIKE 'é%', parse_timestamp(NULL, 'yyyy-MM-dd') IS NULL]",
  )
  let checked = check_patterns(context, pattern_limits()).unwrap()
  assert_eq(pattern_count(checked), 9)
  for i in 0..<9 {
    match i % 3 {
      0 => assert_true(pattern_at(checked, i) is Some(Regex(_)))
      1 => assert_true(pattern_at(checked, i) is Some(Like(_)))
      _ => assert_true(pattern_at(checked, i) is Some(Timestamp(_)))
    }
  }
  let used = pattern_usage(checked)
  let exact : PatternLimits = {
    ..pattern_limits(),
    max_work: used.work,
    max_text_bytes: used.text_bytes,
    max_ast_bytes: used.ast_bytes,
    max_ast_nodes: used.ast_nodes,
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
  let like = check_like_patterns(context, {
    max_work: 1000000,
    max_text_bytes: 1000000,
  }).unwrap()
  assert_eq(like_pattern_count(like), 3)
  assert_true(physical_equal(like_pattern_context(like), context))
  assert_true(like_pattern_at(like, -1) is None)
  assert_true(like_pattern_at(like, 3) is None)
  let u = like_pattern_usage(like)
  assert_true(
    check_like_patterns(context, {
      max_work: u.work,
      max_text_bytes: u.text_bytes,
    })
    is Ok(_),
  )
  assert_true(
    check_like_patterns(context, {
      max_work: u.work - 1,
      max_text_bytes: u.text_bytes,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_like_patterns(context, {
      max_work: u.work,
      max_text_bytes: u.text_bytes - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_like_patterns(context, { max_work: -1, max_text_bytes: 0, })
    is Err(InvalidLimits),
  )
}
