///|
fn limit_parameter_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","select":["id","amount"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"take":{"count":{"$param":"p"},"offset":{"$param":"p"}},"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "LIMIT Parameters match an independently checked complete Program" {
  let expected = limit_parameter_expected()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Checked(_),
    msg="the common take contract already supports bound count and offset",
  )
  for
    text in [
      "SELECT id, amount FROM orders ORDER BY id LIMIT @p OFFSET @p", "FROM orders |> SELECT id, amount |> ORDER BY id |> LIMIT @p OFFSET @p",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..values_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "LIMIT Parameters retain missing declarations values and integer refusals" {
  let query = @query.parse_query(
    "SELECT id FROM orders ORDER BY id LIMIT @p OFFSET @p",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    {
      ..values_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  for value in ["0", "-1", "1.5", "null", "9007199254740992", "\"private\""] {
    assert_true(
      @check.check_parsed(
        program,
        check_environment(),
        Some(analytic_frame_parameter_values(value)),
        check_limits(),
      )
      is Rejected(_),
      msg=value,
    )
  }
  let undeclared = compile(query, values_context(), construction_limits()).unwrap()
  assert_true(
    @check.check_parsed(
      undeclared,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Rejected(_),
  )
}

///|
test "LIMIT Parameters survive set and JOIN final operation lowering" {
  for
    (text, context) in [
      (
        "SELECT 2 AS id UNION ALL SELECT 1 AS id ORDER BY id LIMIT @p OFFSET @p",
        values_context(),
      ),
      (
        "WITH chosen AS (SELECT id FROM orders ORDER BY id LIMIT @p OFFSET @p) SELECT id FROM chosen ORDER BY id LIMIT @p",
        values_context(),
      ),
      (
        "SELECT t.x AS id FROM t JOIN r ON t.x = r.k ORDER BY id LIMIT @p OFFSET @p",
        join_order_context(),
      ),
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..context,
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"count\":{\"$param\":\"p\"}"))
    assert_true(semantic(program).contains("\"offset\":{\"$param\":\"p\"}"))
    match
      @check.check_parsed(
        program,
        check_environment(),
        Some(analytic_frame_parameter_values("1")),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("all Parameters are bound in the independent Values fixtures")
    }
  }
}
