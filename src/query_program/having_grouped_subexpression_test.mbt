///|
test "HAVING grouped subexpressions reuse a checked key in an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"filter":{"gt":[{"add":[{"field":"n"},{"field":"aql_group_key_0"}]},{"literal":8}]}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ordinary filter reads the evaluated grouping key")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT COUNT(*) AS n FROM pair GROUP BY x + 1 HAVING n + (pair.x + 1) > 8",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "HAVING grouped subexpressions do not substitute input keys for computed aliases" {
  let actual = compile(
    @query.parse_query(
      "SELECT -x AS x, COUNT(*) AS n FROM t GROUP BY t.x HAVING x + 1 > 0",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_having_expr_4":{"negate":{"field":"x"}}}},{"filter":{"gt":[{"add":[{"field":"aql_having_expr_4"},{"literal":1}]},{"literal":0}]}},{"select":[{"x":"aql_having_expr_4"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("HAVING reads the evaluated negative alias")
  }
}

///|
test "HAVING grouped subexpressions keep nullable property and range meanings" {
  for
    source in [
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING n + (objects.payload.score + 1) > 12 ORDER BY bucket",
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING COUNT(*) + (`objects`.`payload`.`score` + 1) > 12 ORDER BY bucket",
      "SELECT payload.score + 1 AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING payload + 1 > 12 ORDER BY payload",
      "SELECT payload.score + 1 AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING objects.payload.score + 1 > 12 ORDER BY payload",
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY payload.score + 1 HAVING n + (payload.score + 1) > 12 ORDER BY bucket",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail("checker rejected: " + source)
    }
  }
}

///|
test "HAVING grouped subexpressions retain JOIN and CTE scope" {
  for
    source in [
      "SELECT l.x + 1 AS bucket, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x GROUP BY l.x + 1 HAVING COUNT(*) + (l.x + 1) > 0 ORDER BY bucket",
      "WITH summarized AS (SELECT x + 1 AS bucket, COUNT(*) AS n FROM t GROUP BY x + 1 HAVING n + (t.x + 1) > 0) SELECT bucket, n FROM summarized ORDER BY bucket",
      "SELECT x + 1 AS bucket, COUNT(*) AS n FROM t GROUP BY x + 1 HAVING n + (x + 1) > 0 |> WHERE n > 0 |> ORDER BY bucket",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
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
      _ => fail("HAVING retains grouped JOIN and CTE values: " + source)
    }
  }
}

///|
test "HAVING grouped subexpressions refuse ungrouped and ambiguous receivers" {
  for
    source in [
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING payload.score > 10",
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING other.score + 1 > 10",
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING payload.score + 2 > 10",
      "SELECT payload.score + 1 AS bucket, other.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING bucket > 10",
      "SELECT COUNT(*) AS n FROM objects AS current GROUP BY current.payload.score + 1 HAVING old.payload.score + 1 > 10",
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING aql_pipe_group_bound_0 > 10",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "HAVING grouped subexpressions preserve work limits and original origins" {
  let query = @query.parse_query(
    "SELECT COUNT(*) AS n FROM pair GROUP BY x + 1 HAVING n + (pair.x + 1) > 8",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, pair_context(), {
      ..construction_limits(),
      max_expression_work: 20,
    })
    is Err(Expression({ issue: @expression.WorkLimit, origin: Some(_), })),
  )
}

///|
test "HAVING grouped subexpressions compare alias property receivers in their own scope" {
  let context = {
    ..group_property_context(),
    parameter_declarations: Some(having_object_declarations()),
  }
  for
    (condition, property_count) in [
      ("payload.score + 1 > 12", 2),
      ("objects.payload.score + 1 > 12", 1),
    ] {
    let program = compile(
      @query.parse_query(
        "SELECT payload.score + 1 AS bucket, @assessment AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING " +
        condition +
        " ORDER BY bucket",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(),
        Some(having_object_values()),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the constant alias retains its nullable object contract")
    }
    let body = semantic(program)
    assert_eq(body.split("\"property\":").length() - 1, property_count)
    assert_eq(body.split("\"$param\":").length() - 1, 1)
  }
}
