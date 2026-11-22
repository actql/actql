///|
test "SQL TIMESTAMP_TRUNC supports the original date part and nullable Timestamp" {
  let program = compile(
    @query.parse_query(
      "WITH t AS (SELECT TIMESTAMP '1969-12-31 23:59:59.999999+00' AS ts) SELECT TIMESTAMP_TRUNC(ts, dAy) AS day_start, TIMESTAMP_TRUNC(ts, MICROSECOND) AS at_micros, TIMESTAMP_TRUNC(NULL, SECOND) AS missing FROM t",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  let identity = semantic(program)
  assert_eq(identity.split("\"timestamp_trunc\":").length(), 4)
  for unit in ["d", "us", "s"] {
    assert_true(identity.contains("{\"literal\":\"" + unit + "\"}"))
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("authored timestamps require no inputs")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "SQL TIMESTAMP_TRUNC requires its selected unit and original Timestamp domain" {
  let stamp = "TIMESTAMP '2026-01-02 03:04:05+00'"
  for
    unit in [
      "'d'", "`DAY`", "MONTH", "NANOSECOND", "DAY + 1", "DAY, 'America/Los_Angeles'",
    ] {
    let text = "SELECT TIMESTAMP_TRUNC(" + stamp + ", " + unit + ") AS x"
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
  for operand in ["1", "'2026-01-02T03:04:05.000Z'", "DATE '2026-01-02'"] {
    let text = "SELECT TIMESTAMP_TRUNC(" + operand + ", DAY) AS x"
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=text,
    )
  }
}
