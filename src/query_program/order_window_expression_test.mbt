///|
fn order_window_expression_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"amount","dir":"desc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"functions":{"aql_order_window_0":{"fn":"row_number"}}}},{"sort":[{"field":"aql_order_window_0","dir":"desc","nulls":"last"}]},{"select":["id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent ORDER window Program passes the ordinary checker" {
  match
    @check.check_parsed(
      order_window_expression_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values window control is closed")
  }
}

///|
test "SQL ORDER window matches the independent complete Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT id FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY amount DESC, id) DESC",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(order_window_expression_expected()))
}

///|
fn checked_order_window(text : String) -> String raise {
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ORDER window control must be closed: " + text)
  }
  semantic(actual)
}

///|
test "ORDER STRING_AGG preserves common collection ceiling in SQL Pipe and set scopes" {
  let call = "STRING_AGG('x', '|') OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) DESC, id DESC"
  for
    source in [
      "SELECT id FROM orders ORDER BY " + call,
      "FROM orders |> SELECT id |> ORDER BY " + call,
      "SELECT id FROM orders UNION ALL SELECT id FROM orders ORDER BY " + call,
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let actual = compile(query, values_context(), {
      ..construction_limits(),
      max_collection_bytes: 17L,
    }).unwrap()
    let wire = semantic(actual)
    assert_true(wire.contains("\"max_bytes\":17"), msg=wire)
    assert_true(wire.contains("\"delimiter\":\"|\""), msg=wire)
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail(source)
    }
    for bound in [0L, -1L, 9007199254740992L] {
      assert_true(
        compile(query, values_context(), {
          ..construction_limits(),
          max_collection_bytes: bound,
        })
        is Err(UnsupportedAggregate),
        msg=source,
      )
    }
  }
}

///|
test "ORDER windows consume evaluated SELECT aliases in arguments and OVER keys" {
  let text = checked_order_window(
    "SELECT id, -amount AS amount FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY amount, id) DESC",
  )
  assert_eq(text.split("\"negate\":").length() - 1, 1)
  assert_true(text.contains("\"field\":\"aql_order_alias_4\""))
  assert_true(text.contains("{\"amount\":\"aql_order_alias_4\"}"))
  for
    source in [
      "SELECT id, amount + 1 AS computed FROM orders ORDER BY LAG(computed) OVER (ORDER BY id) NULLS LAST, id",
      "SELECT id, amount + 1 AS computed FROM orders ORDER BY ROW_NUMBER() OVER (PARTITION BY computed ORDER BY id) DESC, id",
      "SELECT id, -amount AS amount FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY orders.amount, id) DESC",
      "SELECT customer_id, COUNT(*) AS total FROM orders GROUP BY customer_id ORDER BY ROW_NUMBER() OVER (ORDER BY total, customer_id) DESC",
      "SELECT customer_id, COUNT(*) + 1 AS total FROM orders GROUP BY customer_id ORDER BY ROW_NUMBER() OVER (ORDER BY total, customer_id) DESC",
      "SELECT * FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC", "SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM orders QUALIFY n > 1 ORDER BY ROW_NUMBER() OVER (ORDER BY amount DESC, id) DESC",
      "SELECT id FROM orders ORDER BY -ROW_NUMBER() OVER (ORDER BY id), RANK() OVER (ORDER BY amount) DESC",
    ] {
    ignore(checked_order_window(source))
  }
}

///|
test "Pipe ORDER windows consume current rows and remove temporary outputs" {
  for
    source in [
      "FROM orders |> ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC |> SELECT *",
      "FROM orders |> SELECT id, -amount AS amount |> ORDER BY ROW_NUMBER() OVER (ORDER BY amount, id) DESC |> SELECT *",
      "FROM orders |> SELECT DISTINCT amount |> ORDER BY ROW_NUMBER() OVER (ORDER BY amount) DESC |> SELECT *",
      "FROM orders AS old |> AS current |> ORDER BY ROW_NUMBER() OVER (ORDER BY current.id) DESC |> SELECT *",
    ] {
    let text = checked_order_window(source)
    assert_true(!text.contains("\"fields\":[\"aql_order_window_"))
  }
  let text = checked_order_window(
    "FROM orders |> ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC |> SELECT *",
  )
  assert_true(
    text.contains("\"select\":[\"id\",\"customer_id\",\"status\",\"amount\"]"),
    msg=text,
  )
}

///|
test "set ORDER windows run after combination over output columns" {
  for
    text in [
      "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY ROW_NUMBER() OVER (ORDER BY a, b) DESC",
      "SELECT a AS x, b FROM left_rows UNION DISTINCT SELECT c AS y, d FROM right_rows ORDER BY -ROW_NUMBER() OVER (ORDER BY x, b)",
      "WITH chosen AS (SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY ROW_NUMBER() OVER (ORDER BY a, b) DESC) SELECT a, b FROM chosen",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail(text)
    }
  }
}

///|
test "ORDER windows reject nested SELECT window aliases at the intended boundary" {
  for
    text in [
      "SELECT ROW_NUMBER() OVER (ORDER BY id) AS n FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY n)",
      "SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 AS n FROM orders ORDER BY ROW_NUMBER() OVER (PARTITION BY n ORDER BY id)",
      "SELECT ROW_NUMBER() OVER (ORDER BY id) AS n FROM orders ORDER BY LAG(n) OVER (ORDER BY id)",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
      msg=text,
    )
  }
}

///|
test "ORDER windows reject DISTINCT-owned calls and named windows precisely" {
  assert_true(
    @query.parse_query(
      "SELECT DISTINCT id FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY id)",
      syntax_limits(),
    )
    is Err(
      {
        issue: @query.Syntax(
          "Analytic ORDER BY is not allowed after SELECT DISTINCT"
        ),
        ..
      }
    ),
  )
  assert_true(
    @query.parse_query(
      "SELECT id FROM orders WINDOW w AS (ORDER BY id) ORDER BY ROW_NUMBER() OVER w",
      syntax_limits(),
    )
    is Err(
      { issue: @query.Syntax("Named window is not allowed in ORDER BY"), .. }
    ),
  )
  assert_true(
    compile(
      @query.parse_query(
        "FROM orders |> SELECT id |> ORDER BY ROW_NUMBER() OVER (ORDER BY amount)",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "ORDER alias snapshot matches an independently authored complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","derive":{"aql_order_alias_4":{"negate":{"field":"amount"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"aql_order_alias_4","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"functions":{"aql_order_window_0":{"fn":"row_number"}}}},{"sort":[{"field":"aql_order_window_0","dir":"desc","nulls":"last"}]},{"select":["id",{"amount":"aql_order_alias_4"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent ORDER alias control is closed")
  }
  assert_eq(
    checked_order_window(
      "SELECT id, -amount AS amount FROM orders ORDER BY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) DESC",
    ),
    semantic(expected),
  )
}
