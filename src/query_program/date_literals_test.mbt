///|
test "SQL DATE literal preserves the original Gregorian Date contract" {
  for
    (source, expected) in [
      ("SELECT DATE '2026-01-02' AS x", "2026-01-02"),
      ("SELECT date '2024-' '2-9' AS x", "2024-02-09"),
      ("SELECT DATE '0001-1-1' AS x", "0001-01-01"),
      ("SELECT DATE '9999-12-31' AS x", "9999-12-31"),
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(program).contains("\"date_literal\":\"" + expected + "\""),
      msg=source,
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) =>
        fail("a calendar literal has no source or policy inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "SQL DATE literal refuses impossible civil dates before execution" {
  for date in ["0000-02-29", "1900-02-29", "2026-04-31", "2026-13-01"] {
    let program = compile(
      @query.parse_query("SELECT DATE '" + date + "' AS x", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    match program {
      Err(_) => ()
      Ok(program) =>
        match
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          ) {
          Rejected(_) => ()
          _ => fail("impossible civil date was admitted: " + date)
        }
    }
  }
}
