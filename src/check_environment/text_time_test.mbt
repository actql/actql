///|
fn text_time_body() -> String {
  "{\"max_input_codepoints\":1,\"max_input_utf8_bytes\":1,\"max_output_bytes\":1,\"max_pattern_bytes\":1,\"max_replacements\":1,\"version\":\"actql-text-time-host-policy/0.1\"}"
}

///|
test "text-time component retains selected environment and independent policy CID" {
  let environment = capacity_wire(
    "{\"text_time_evaluation\":" + text_time_body() + "}",
  )
  let limits : @text_policy.Limits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 4,
  }
  let component = read_text_time(environment, limits).unwrap()
  assert_true(physical_equal(text_time_environment(component), environment))
  assert_eq(
    @text_policy.cid(text_time_policy(component)),
    "sha256:5fac567c3a4cc4da2a9494a9fc7b0d2304157c3641100f73e752426e62c8d8c1",
  )
  assert_eq(text_time_usage(component), (text_time_body().length(), 7))
  let other = capacity_wire(
    "{\"text_time_evaluation\":" + text_time_body() + "}",
  )
  assert_false(physical_equal(text_time_environment(component), other))
  let exact : @text_policy.Limits = {
    max_bytes: text_time_body().length(),
    max_nodes: 7,
    max_depth: 1,
  }
  assert_true(read_text_time(environment, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_bytes: exact.max_bytes - 1, },
      { ..exact, max_nodes: 6, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      read_text_time(environment, cap) is Err(TextTimeIssue::BudgetExceeded),
    )
  }
  assert_true(
    read_text_time(environment, { ..exact, max_bytes: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "missing text-time policy stays unresolved and supplied invalid values reject" {
  let limits : @text_policy.Limits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 4,
  }
  assert_true(
    read_text_time(capacity_wire("{}"), limits) is Err(MissingTextTime),
  )
  for bad in ["null", "[]", "false"] {
    assert_true(
      read_text_time(
        capacity_wire("{\"text_time_evaluation\":" + bad + "}"),
        limits,
      )
      is Err(InvalidComponent),
    )
  }
  assert_true(
    read_text_time(capacity_wire("{\"text_time_evaluation\":{}}"), limits)
    is Err(Policy(_)),
  )
  let bad = text_time_body().replace(
    old="\"max_pattern_bytes\":1",
    new="\"max_pattern_bytes\":0",
  )
  assert_true(
    read_text_time(
      capacity_wire("{\"text_time_evaluation\":" + bad + "}"),
      limits,
    )
    is Err(Policy(@text_policy.InvalidCeiling("max_pattern_bytes"))),
  )
}
