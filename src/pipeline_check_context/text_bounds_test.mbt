///|
fn bound_limits() -> TextBoundsLimits {
  { max_work: 1000000, max_text_bytes: 1000000, }
}

///|
fn bound_profile() -> String {
  validation_profile(
    (
      #|{"max_input_codepoints":1000,"max_input_utf8_bytes":4000,"max_output_bytes":100000,"max_pattern_bytes":100,"max_replacements":1001,"version":"actql-text-time-host-policy/0.1"}
    ),
  )
}

///|
fn bound_fixture(
  expression : String,
  parameters? : String = "{\"p\":{\"type\":\"string\",\"default\":\"é😀\"},\"n\":{\"type\":\"number\",\"default\":1}}",
  supplied? : @decode.Cursor? = None,
  profile? : String = bound_profile(),
  steps? : String? = None,
) -> PatternChecks {
  check_patterns(
    regex_fixture(expression, parameters~, supplied~, profile~, steps~),
    pattern_limits(),
  ).unwrap()
}

///|
test "text bounds resolve every portable formula from owned expression sites" {
  let examples = [
    ("split_part('é😀', ',', 1)", 6L),
    ("substring('é😀', 1, 1)", 4L),
    ("utf8_truncate('é😀', 3)", 3L),
    ("try_number('1')", 32L),
    ("nfkc('é😀')", 144L),
    ("case_fold('é😀')", 32L),
    ("parse_timestamp('2020-01-01', 'yyyy-MM-dd')", 24L),
    ("try_timestamp('invalid', 'yyyy-MM-dd')", 24L),
    ("format_timestamp(CAST(NULL AS TIMESTAMP), 'yyyy')", 4L),
    ("regex_match('é😀', '.')", 5L),
    ("regex_extract('é😀', '(.)', 1)", 6L),
    ("regex_replace('é😀', '(.)', '$1x')", 27L),
  ]
  for (expression, expected) in examples {
    let patterns = bound_fixture(expression)
    let checks = check_text_bounds(patterns, bound_limits()).unwrap()
    assert_true(physical_equal(text_bounds_patterns(checks), patterns))
    assert_eq(text_bound_count(checks), 3)
    for i in 0..<3 {
      let v = text_bound_at(checks, i).unwrap()
      assert_eq(@bounds.output_bytes(text_bound_output(v)), expected)
      assert_true(
        physical_equal(
          validation_site_context(text_bound_site(v)),
          pattern_context(patterns),
        ),
      )
      assert_true(
        physical_equal(
          text_bound_policy(v),
          expression_validation_text_time(pattern_context(patterns)).unwrap(),
        ),
      )
      assert_true(
        validation_site_requirement(text_bound_site(v)).obligation.kind
        is HostEnvelope,
      )
      assert_true(
        physical_equal(
          @typing.demand_expression(text_bound_demands(v)),
          validation_site_requirement(text_bound_site(v)).expression,
        ),
      )
    }
    assert_true(text_bound_at(checks, -1) is None)
    assert_true(text_bound_at(checks, 3) is None)
  }
}

///|
test "text bounds preserve selected values and direct child derivations" {
  let patterns = bound_fixture(
    "substring(nfkc($p), 1, $n)",
    supplied=Some(cursor("{\"p\":\"é😀\",\"n\":2}")),
  )
  let checks = check_text_bounds(patterns, bound_limits()).unwrap()
  assert_eq(text_bound_count(checks), 6)
  for i in 0..<3 {
    // Derive children first, but return the original preorder inventory.
    let parent = text_bound_at(checks, i * 2).unwrap()
    let child = text_bound_at(checks, i * 2 + 1).unwrap()
    assert_eq(@bounds.output_bytes(text_bound_output(child)), 144L)
    assert_eq(@bounds.output_bytes(text_bound_output(parent)), 8L)
    assert_true(
      physical_equal(
        @bounds.input_producer(@bounds.output_input(text_bound_output(parent))).unwrap(),
        text_bound_output(child),
      ),
    )
    assert_eq(
      @bounds.input_origin(@bounds.output_input(text_bound_output(child))),
      @bounds.KnownValue,
    )
    assert_eq(text_bound_input_parameter(child).unwrap().name, "p")
    assert_eq(text_bound_length_parameter(parent).unwrap().name, "n")
    assert_true(
      physical_equal(
        text_bound_input_parameter(child).unwrap().value,
        @bounds.input_value(@bounds.output_input(text_bound_output(child))).unwrap(),
      ),
    )
  }
  let patterns = bound_fixture(
    "nfkc(substring('abc', 1, $n))",
    parameters="{\"n\":{\"type\":\"number\",\"nullable\":true,\"default\":null}}",
  )
  let checks = check_text_bounds(patterns, bound_limits()).unwrap()
  for i in 0..<text_bound_count(checks) {
    assert_true(
      @bounds.output_contract(
        text_bound_output(text_bound_at(checks, i).unwrap()),
      ).nullable,
    )
  }
}

///|
test "text bounds retain runtime input preflight and never evaluate dynamic lengths" {
  let checks = check_text_bounds(
    bound_fixture("nfkc(concat('a', 'b'))"),
    bound_limits(),
  ).unwrap()
  let input = @bounds.output_input(
    text_bound_output(text_bound_at(checks, 0).unwrap()),
  )
  assert_eq(@bounds.input_origin(input), @bounds.RuntimePreflight)
  assert_eq(@bounds.input_extent(input), (1000L, 4000L))
  assert_eq(
    @bounds.output_bytes(text_bound_output(text_bound_at(checks, 0).unwrap())),
    72000L,
  )
  for
    expression in [
      "substring('abc', 1, -1)", "substring('abc', 1, 1 / 0)", "substring('abc', 1, $n)",
    ] {
    let checks = check_text_bounds(
      bound_fixture(expression, supplied=Some(cursor("{\"n\":-1}"))),
      bound_limits(),
    ).unwrap()
    assert_eq(
      @bounds.output_bytes(text_bound_output(text_bound_at(checks, 0).unwrap())),
      3L,
    )
  }
  // Known null is exact zero, but function output laws are not constant folded.
  let checks = check_text_bounds(bound_fixture("nfkc(NULL)"), bound_limits()).unwrap()
  assert_eq(
    @bounds.input_origin(
      @bounds.output_input(text_bound_output(text_bound_at(checks, 0).unwrap())),
    ),
    @bounds.KnownValue,
  )
  assert_eq(
    @bounds.output_bytes(text_bound_output(text_bound_at(checks, 0).unwrap())),
    0L,
  )
}

///|
test "text bound checks share cumulative limits and reject late static failures" {
  let patterns = bound_fixture("substring(nfkc($p), 1, $n)")
  let checks = check_text_bounds(patterns, bound_limits()).unwrap()
  let usage = text_bounds_usage(checks)
  let exact : TextBoundsLimits = {
    max_work: usage.work,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(check_text_bounds(patterns, exact) is Ok(_))
  assert_true(
    check_text_bounds(patterns, { ..exact, max_work: usage.work - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_text_bounds(patterns, {
      ..exact,
      max_text_bytes: usage.text_bytes - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_text_bounds(patterns, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
  let patterns = bound_fixture("nfkc(NULL)", profile=capacity_profile(false))
  assert_true(
    check_text_bounds(patterns, bound_limits()) is Err(MissingPolicy(1)),
  )
  let patterns = bound_fixture(
    "[nfkc(NULL), nfkc('ab')]",
    profile=validation_profile(valid_text_policy()),
  )
  assert_true(
    check_text_bounds(patterns, bound_limits())
    is Err(Bounds(_, @bounds.InputCeiling)),
  )
  let patterns = bound_fixture(
    "if(TRUE, '', nfkc('ab'))",
    profile=bound_profile().replace(
      old="\"max_output_bytes\":100000",
      new="\"max_output_bytes\":100",
    ),
  )
  assert_true(
    check_text_bounds(patterns, bound_limits())
    is Err(Bounds(_, @bounds.OutputCeiling)),
  )
  let patterns = bound_fixture(
    "case_fold(nfkc('é😀'))",
    profile=bound_profile().replace(
      old="\"max_input_utf8_bytes\":4000",
      new="\"max_input_utf8_bytes\":100",
    ),
  )
  assert_true(
    check_text_bounds(patterns, bound_limits())
    is Err(Bounds(_, @bounds.InputCeiling)),
  )
  let patterns = bound_fixture("NULL LIKE 'a%'")
  assert_eq(
    text_bound_count(check_text_bounds(patterns, bound_limits()).unwrap()),
    0,
  )
}

///|
test "text bounds retain derived conditional demand without evaluating it" {
  let patterns = bound_fixture("if(TRUE, 'selected', nfkc('unselected'))")
  let checked = check_text_bounds(patterns, bound_limits()).unwrap()
  for i in 0..<text_bound_count(checked) {
    let entry = text_bound_at(checked, i).unwrap()
    let demand = text_bound_demands(entry)
    let node = validation_site_requirement(text_bound_site(entry)).obligation.node_index
    assert_eq(
      @typing.demand_pointer(demand, node, max_bytes=100).unwrap(),
      Some("/if/2"),
    )
    let tests = @typing.demand_tests(demand, node, max_tests=1).unwrap()
    assert_eq(tests.length(), 1)
    assert_eq(tests[0].kind, @typing.NotTrue)
    assert_eq(
      @typing.demand_pointer(demand, tests[0].node_index, max_bytes=100).unwrap(),
      Some("/if/0"),
    )
  }
}
