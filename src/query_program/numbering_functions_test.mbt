///|
test "original SQL NTILE and PERCENT_RANK reach common analytic checking" {
  let inputs = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) "
  for
    (function, wire) in [
      ("NTILE(2)", "ntile"),
      ("PERCENT_RANK()", "percent_rank"),
    ] {
    let program = compile(
      @query.parse_query(
        inputs + "SELECT " + function + " OVER (ORDER BY n) AS result FROM t",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"fn\":\"" + wire + "\""))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the original SQL has no external inputs")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "NTILE requires a positive whole bound parameter" {
  let program = compile(
    @query.parse_query(
      "SELECT NTILE(@p) OVER (ORDER BY id) AS result FROM orders",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_true(semantic(program).contains("\"buckets\":{\"$param\":\"p\"}"))
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  assert_true(
    @check.check_parsed(
      program,
      check_environment(),
      Some(grouped_analytic_offset_values("{\"p\":2}")),
      check_limits(),
    )
    is Checked(_),
  )
  for value in ["0", "-1", "1.5", "null", "9007199254740992"] {
    assert_true(
      @check.check_parsed(
        program,
        check_environment(),
        Some(grouped_analytic_offset_values("{\"p\":" + value + "}")),
        check_limits(),
      )
      is Rejected(_),
      msg=value,
    )
  }
}
