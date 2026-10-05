///|
fn grouped_in_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","filter":{"in":[{"field":"amount"},{"literal":[{"$param":"p"},-2]}]}},{"select":["id"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn grouped_in_parameter(value : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(value, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "independent grouped IN Program uses the ordinary parameter checker" {
  let expected = grouped_in_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(grouped_in_parameter("{\"p\":1}")),
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "SQL and Pipe grouped IN atoms match a complete independent Program" {
  for
    text in [
      "SELECT id FROM orders WHERE amount IN ((@p), -(2)) ORDER BY id", "FROM orders |> WHERE amount IN (((@p)), -((2))) |> SELECT id |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..values_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(grouped_in_expected()))
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(grouped_in_parameter("{\"p\":1}")),
        check_limits(),
      )
      is Checked(_),
    )
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(grouped_in_parameter("{\"p\":\"wrong\"}")),
        check_limits(),
      )
      is Rejected(_),
    )
  }
}
