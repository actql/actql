///|
fn grouped_analytic_offset_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"previous":{"fn":"lag","expr":{"field":"amount"},"offset":2},"next":{"fn":"lead","expr":{"field":"amount"},"offset":{"$param":"p"}}}}},{"select":["id","previous","next"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","previous","next"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn grouped_analytic_offset_values(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "independent navigation offset Program keeps common parameter validation" {
  let expected = grouped_analytic_offset_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(grouped_analytic_offset_values("{\"p\":1}")),
      check_limits(),
    )
    is Checked(_),
  )
  for value in ["-1", "1.5", "null", "9007199254740992", "\"private\""] {
    assert_true(
      @check.check_parsed(
        expected,
        check_environment(),
        Some(grouped_analytic_offset_values("{\"p\":" + value + "}")),
        check_limits(),
      )
      is Rejected(_),
    )
  }
}

///|
test "SQL and Pipe grouped navigation offsets match the independent Program" {
  for
    text in [
      "SELECT id, LAG(amount, (2)) OVER (ORDER BY id) AS previous, LEAD(amount, ((@p))) OVER (ORDER BY id) AS next FROM orders ORDER BY id",
      "FROM orders |> SELECT id, LAG(amount, ((2))) OVER (ORDER BY id) AS previous, LEAD(amount, (@p)) OVER (ORDER BY id) AS next |> ORDER BY id",
    ] {
    let actual = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        {
          ..values_context(),
          parameter_declarations: Some(number_parameter_declarations()),
        },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedAnalytic) => fail("Grouping must retain the offset atom")
      Err(_) => fail("Unexpected Frontend rejection")
    }
    assert_eq(semantic(actual), semantic(grouped_analytic_offset_expected()))
  }
}

///|
test "grouped navigation offsets preserve literal bounds and refuse computation" {
  for value in ["((0))", "(9007199254740991)"] {
    let program = compile(
      @query.parse_query(
        "SELECT LAG(amount, " +
        value +
        ") OVER (ORDER BY id) AS previous FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
  for
    value in [
      "(9007199254740992)", "(1.5)", "(-1)", "(amount)", "(@p + 1)", "(1 + 1)", "(NULL)",
      "('2')",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT LEAD(amount, " +
          value +
          ") OVER (ORDER BY id) AS next FROM orders",
          syntax_limits(),
        ).unwrap(),
        {
          ..values_context(),
          parameter_declarations: Some(number_parameter_declarations()),
        },
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
      msg=value,
    )
  }
}

///|
test "grouped navigation offset traversal is bounded with its source origin" {
  let query = @query.parse_query(
    "SELECT LAG(amount, (((2)))) OVER (ORDER BY id) AS previous FROM orders",
    syntax_limits(),
  ).unwrap()
  match
    compile(query, values_context(), {
      ..construction_limits(),
      max_expression_work: 2,
    }) {
    Err(Expression({ issue: WorkLimit, origin: Some(_), })) => ()
    _ => fail("Offset grouping must consume the expression work budget")
  }
}

///|
test "grouped OFFSET composes with derived OVER ordering in SQL and Pipe" {
  // Four input fields and one analytic output reserve the private sort slot.
  // This machine Program is authored independently of compiler output.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","derive":{"aql_analytic_sort_5":{"negate":{"field":"amount"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"aql_analytic_sort_5","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"functions":{"previous":{"fn":"lag","expr":{"field":"amount"},"offset":1}}}},{"select":["id","amount","previous"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount","previous"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
      "SELECT id, amount, LAG(amount, ((1))) OVER (ORDER BY -amount NULLS LAST, id) AS previous FROM orders ORDER BY id",
      "FROM orders |> SELECT id, amount, LAG(amount, (1)) OVER (ORDER BY (-amount) NULLS LAST, (id)) AS previous |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}
