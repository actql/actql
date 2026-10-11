///|
test "number extrema preserve independent complete SQL literal Programs" {
  for name in ["greatest", "least"] {
    for
      (arguments, children) in [
        ("7", "[{\"literal\":7}]"),
        (
          "1, -2, 3, 1", "[{\"literal\":1},{\"literal\":-2},{\"literal\":3},{\"literal\":1}]",
        ),
        ("NULL", "[{\"literal\":null}]"),
        ("NULL, NULL", "[{\"literal\":null},{\"literal\":null}]"),
        ("1, NULL", "[{\"literal\":1},{\"literal\":null}]"),
        (
          "NULL, 1 / 0", "[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]",
        ),
      ] {
      let expected = round_trunc_literal_control(
        "{\"" + name + "\":" + children + "}",
      )
      let actual = compile(
        @query.parse_query(
          "SELECT " + name + "(" + arguments + ") AS value",
          syntax_limits(),
        ).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      for program in [actual, expected] {
        match
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          ) {
          Checked(_) => ()
          NeedsInputs(_) => fail("extrema literal needs no acquisition")
          Rejected(issue) => raise @check.diagnostic_cause(issue)
        }
      }
    }
  }
}

///|
test "number extrema type checks every operand without implicit coercion" {
  for name in ["GREATEST", "LEAST"] {
    for
      arguments in [
        "1.25, '2'", "1.25, TRUE", "1.25, CAST('2' AS DECIMAL(2,0))", "'1.25', 2",
        "NULL, '2'", "1.25, B'2'",
      ] {
      let syntax = @query.parse_query(
        "SELECT " + name + "(" + arguments + ") AS value",
        syntax_limits(),
      )
      match syntax {
        Err(_) => ()
        Ok(parsed) =>
          match
            compile(
              parsed,
              { ..fixture_context(), inputs: [], },
              construction_limits(),
            ) {
            Err(_) => ()
            Ok(program) =>
              assert_true(
                @check.check_parsed(
                  program,
                  check_environment(),
                  None,
                  check_limits(),
                )
                is Rejected(_),
              )
          }
      }
    }
  }
}

///|
test "GREATEST and LEAST SQL and Pipe field calls match an independent Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","derive":{"aql_query_expr_0":{"greatest":[{"field":"amount"},{"literal":1},{"field":"amount"}]},"aql_query_expr_1":{"least":[{"field":"amount"},{"literal":1},{"field":"amount"}]}}},{"select":[{"greatest_value":"aql_query_expr_0"},{"least_value":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["greatest_value","least_value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT GREATEST(amount, 1, amount) AS greatest_value, LEAST(amount, 1, amount) AS least_value FROM orders",
      "FROM orders |> SELECT GREATEST(amount, 1, amount) AS greatest_value, LEAST(amount, 1, amount) AS least_value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      fixture_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
    for program in [expected, actual] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("typed extrema fields need no acquisition")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "GREATEST and LEAST refuse empty calls before checking" {
  for name in ["GREATEST", "LEAST"] {
    let source = "SELECT " + name + "() AS value"
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.InvalidArguments, .. })),
      msg=source,
    )
  }
}
