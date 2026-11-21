///|
test "original ordered FIRST_VALUE and LAST_VALUE use the omitted frame" {
  let inputs = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) "
  for
    (function, wire) in [
      ("FIRST_VALUE(v)", "first_value"),
      ("LAST_VALUE(v)", "last_value"),
    ] {
    let program = compile(
      @query.parse_query(
        inputs + "SELECT " + function + " OVER (ORDER BY n) AS result FROM t",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    let authored = semantic(program)
    assert_true(authored.contains("\"fn\":\"" + wire + "\""))
    assert_true(!authored.contains("\"frame\":"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the original SQL has no external inputs")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}
