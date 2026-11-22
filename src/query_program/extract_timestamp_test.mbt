///|
test "SQL EXTRACT preserves the original CAST and static UTC part" {
  let source = "SELECT EXTRACT(YEAR FROM CAST('2026-01-02T03:04:05.000Z' AS TIMESTAMP)) AS year_part, EXTRACT(dAyOfYeAr FROM NULL) AS absent"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  let identity = semantic(program)
  assert_eq(identity.split("\"extract_timestamp\":").length(), 3)
  assert_true(identity.contains("{\"literal\":\"year\"}"))
  assert_true(identity.contains("{\"literal\":\"dayofyear\"}"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("authored temporal expressions require no input")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "SQL EXTRACT refuses alternate parts, argument syntax and implicit Timestamp conversion" {
  for
    text in [
      "SELECT EXTRACT('YEAR' FROM NULL) AS x", "SELECT EXTRACT(`YEAR` FROM NULL) AS x",
      "SELECT EXTRACT(WEEK FROM NULL) AS x", "SELECT EXTRACT(YEAR, NULL) AS x", "SELECT EXTRACT(YEAR FROM NULL AT TIME ZONE 'America/Los_Angeles') AS x",
    ] {
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
  for operand in ["1", "'2026-01-02T03:04:05.000Z'", "DATE '2026-01-02'"] {
    let text = "SELECT EXTRACT(YEAR FROM " + operand + ") AS x"
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
