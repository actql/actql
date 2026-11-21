///|
test "SQL TIMESTAMP_DIFF checks authored and nullable Timestamp operands" {
  let program = compile(
    @query.parse_query(
      "WITH t AS (SELECT TIMESTAMP '2026-01-02 03:04:05+00' AS a, TIMESTAMP '2026-01-02 00:00:00+00' AS b) SELECT TIMESTAMP_DIFF(a, b, hOuR) AS hours, TIMESTAMP_DIFF(NULL, a, MICROSECOND) AS missing FROM t",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  let identity = semantic(program)
  assert_eq(identity.split("\"timestamp_diff\":").length(), 3)
  assert_true(identity.contains("{\"literal\":\"h\"}"))
  assert_true(identity.contains("{\"literal\":\"us\"}"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("authored timestamps require no input")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "SQL TIMESTAMP_DIFF requires its original static unit and Timestamp domain" {
  let stamp = "TIMESTAMP '2026-01-02 03:04:05+00'"
  for unit in ["'h'", "`HOUR`", "MONTH", "NANOSECOND", "HOUR + 1", "HOUR, DAY"] {
    let text = "SELECT TIMESTAMP_DIFF(" +
      stamp +
      ", " +
      stamp +
      ", " +
      unit +
      ") AS x"
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
  for operand in ["1", "'2026-01-02T03:04:05.000Z'", "DATE '2026-01-02'"] {
    let text = "SELECT TIMESTAMP_DIFF(" +
      operand +
      ", " +
      stamp +
      ", HOUR) AS x"
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
