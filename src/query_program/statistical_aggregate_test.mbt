///|
fn statistical_expected_program() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","group":{"by":[],"aggregates":{"v":{"fn":"var_pop","expr":{"add":[{"field":"amount"},{"literal":1}]}}}}},{"select":["v"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["v"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn check_statistical_program(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("typed Values statistical aggregate must be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "statistical aggregate source matches independent complete Program" {
  let expected = statistical_expected_program()
  check_statistical_program(expected)
  for
    text in [
      "SELECT VAR_POP(amount + 1) AS v FROM orders", "FROM orders |> AGGREGATE VAR_POP(amount + 1) AS v",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    check_statistical_program(program)
  }
}

///|
test "statistical names and GoogleSQL aliases reach the existing checker" {
  for
    (name, common) in [
      ("VAR_POP", "var_pop"),
      ("VAR_SAMP", "var_samp"),
      ("VARIANCE", "var_samp"),
      ("STDDEV_POP", "stddev_pop"),
      ("STDDEV_SAMP", "stddev_samp"),
      ("STDDEV", "stddev_samp"),
    ] {
    for
      text in [
        "SELECT " + name + "(amount) AS v FROM orders",
        "FROM orders |> AGGREGATE " + name + "(amount) AS v",
        "SELECT id, " +
        name +
        "(amount) AS v FROM orders GROUP BY id HAVING v IS NOT NULL ORDER BY v",
        "SELECT id, " +
        name +
        "(amount + 1) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM orders ORDER BY id",
      ] {
      let program = compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      ).unwrap()
      check_statistical_program(program)
      assert_true(
        semantic(program).contains("\"fn\":\"" + common + "\""),
        msg=text,
      )
    }
  }
}

///|
test "statistical arguments retain input scope and ordinary type validation" {
  for
    text in [
      "SELECT VAR_POP(amount) AS amount FROM orders HAVING amount IS NOT NULL", "SELECT VAR_POP(orders.amount) AS amount FROM orders ORDER BY amount",
      "SELECT id, VAR_POP(orders.amount) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS v FROM orders ORDER BY id",
    ] {
    check_statistical_program(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      ).unwrap(),
    )
  }
  for
    text in [
      "SELECT VAR_POP(status) AS v FROM orders", "SELECT VAR_SAMP(DISTINCT amount) AS v FROM orders",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      )
      is Rejected(_),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT VAR_POP(missing) AS v FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT VAR_POP(amount) OVER (ORDER BY id) AS v FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(UnsupportedAnalytic),
  )
}
