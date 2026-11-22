///|
test "SQL DATE checks exact Gregorian coordinates and retains ordinary CTE numbers" {
  for
    text in [
      "SELECT DATE(2026, 1, 2) AS constructed, DATE(2000, 2, 29) AS leap_day", "SELECT DATE(NULL, 1, 2) AS absent",
      "WITH parts AS (SELECT 2000 AS y, 2 AS m, 29 AS d) SELECT DATE(y,m,d) AS leap_day, y AS ordinary_year, y+1 AS next_year FROM parts",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"make_date\":"), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) =>
        fail("Date construction from authored Values needs no input")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "SQL DATE rejects implicit Number or Text coordinates" {
  for arg in ["2000.0", "2e3", "2000 + 0", "'2000'"] {
    let text = "SELECT DATE(" + arg + ", 2, 29) AS x"
    match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) =>
        assert_true(
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          )
          is Rejected(_),
          msg=text,
        )
      Err(ExpressionTyping(_)) => ()
      Err(_) =>
        fail("unexpected failure before the DATE coordinate check: " + text)
    }
  }
}
