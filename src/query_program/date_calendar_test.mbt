///|
test "SQL calendar operations check the original DATE operands and units" {
  let text = "WITH t AS (SELECT DATE '2000-02-29' AS a, DATE '2000-03-01' AS b) SELECT DATE_ADD(a, INTERVAL 1 DAY) AS next_day, DATE_DIFF(a, b, DAY) AS days, DATE_TRUNC(a, MONTH) AS first_day FROM t"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  for tag in ["date_interval_add", "date_boundary_diff", "date_boundary_trunc"] {
    assert_true(wire.contains("\"" + tag + "\":"))
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) =>
      fail("calendar expressions over authored Date need no inputs")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "SQL calendar operations refuse invalid operand domains and keep quoted units separate" {
  for
    text in [
      "SELECT DATE_ADD(DATE '2026-01-02', 1) AS x", "SELECT DATE_ADD(DATE '2026-01-02', INTERVAL 1 HOUR) AS x",
      "SELECT DATE_DIFF(DATE '2026-01-02', '2026-01-01', DAY) AS x", "SELECT DATE_TRUNC(DATE '2026-01-02', 'MONTH') AS x",
    ] {
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
      Err(_) => ()
    }
  }
  let legacy = compile(
    @query.parse_query(
      "SELECT DATE_DIFF(DATE '2026-01-02', DATE '2026-01-01','d') AS x",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(semantic(legacy).contains("\"date_diff\":"))
}
