///|
test "grouped LIMIT Parameters match the complete independently authored take Program" {
  let expected = limit_parameter_expected()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Checked(_),
  )
  for
    text in [
      "SELECT id, amount FROM orders ORDER BY id LIMIT ((@p)) OFFSET (@p)", "FROM orders |> SELECT id, amount |> ORDER BY id |> LIMIT (@p) OFFSET ((@p))",
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
    for value in ["0", "-1", "1.5", "null", "9007199254740992", "\"private\""] {
      assert_true(
        @check.check_parsed(
          actual,
          check_environment(),
          Some(analytic_frame_parameter_values(value)),
          check_limits(),
        )
        is Rejected(_),
        msg=value,
      )
    }
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is NeedsInputs(_),
    )
  }
}

///|
test "grouped literal LIMIT keeps count offset and complete output contracts" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","select":["id","amount"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"take":{"count":1,"offset":1},"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    text in [
      "SELECT id, amount FROM orders ORDER BY id LIMIT ((1)) OFFSET (1)", "FROM orders |> SELECT id, amount |> ORDER BY id |> LIMIT (1) OFFSET ((1))",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}
