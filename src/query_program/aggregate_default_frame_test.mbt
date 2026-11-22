///|
test "original SQL aggregate default frames pass common checking" {
  let input = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) "
  for function in ["SUM(v)", "COUNT(*)", "AVG(v)", "MIN(v)"] {
    for window in ["ORDER BY n", "PARTITION BY s", ""] {
      let sql = input +
        "SELECT " +
        function +
        " OVER (" +
        window +
        ") AS x FROM t"
      let program = compile(
        @query.parse_query(sql, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_true(!semantic(program).contains("\"frame\":"), msg=sql)
      match
        @check.check_parsed(
          program,
          check_environment(numeric=true),
          None,
          check_limits(),
        ) {
        Checked(_) => ()
        NeedsInputs(_) => fail("the original SQL has no external inputs")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "aggregate default frames keep authored peers without inventing position evidence" {
  let input = "WITH t AS (SELECT 1 AS n, 10 AS v UNION ALL SELECT 1 AS n, 20 AS v) "
  for
    (expression, accepted) in [
      ("SUM(v) OVER (ORDER BY n)", true),
      ("NTILE(2) OVER ()", false),
      ("LAST_VALUE(v) OVER ()", false),
      ("STRING_AGG(CAST(v AS STRING), ',') OVER ()", false),
    ] {
    let sql = input + "SELECT " + expression + " AS x FROM t"
    match
      compile(
        @query.parse_query(sql, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) =>
        assert_eq(
          @check.check_parsed(
            program,
            check_environment(numeric=true),
            None,
            check_limits(),
          )
          is Checked(_),
          accepted,
          msg=sql,
        )
      Err(_) => assert_true(!accepted, msg=sql)
    }
  }
}
