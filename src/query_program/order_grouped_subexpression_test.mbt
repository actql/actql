///|
test "ORDER grouped subexpressions reuse evaluated keys in an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_query_sort_4":{"add":[{"field":"n"},{"field":"aql_group_key_0"}]}}},{"sort":[{"field":"aql_query_sort_4","dir":"asc","nulls":"first"}]},{"select":[{"bucket":"aql_group_key_0"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ordinary derive/sort uses the checked key before final SELECT")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT x + 1 AS bucket, COUNT(*) AS n FROM pair GROUP BY x + 1 ORDER BY n + (pair.x + 1)",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "ORDER grouped subexpressions do not substitute input keys for computed aliases" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_query_expr_0":{"negate":{"field":"x"}}}},{"derive":{"aql_query_sort_4":{"add":[{"field":"aql_query_expr_0"},{"literal":1}]}}},{"sort":[{"field":"aql_query_sort_4","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_query_expr_0"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT -x AS x, COUNT(*) AS n FROM t GROUP BY t.x ORDER BY x + 1",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ORDER reads the evaluated negative alias")
  }
}

///|
test "ORDER grouped subexpressions keep nullable properties and hidden aggregates" {
  for
    source in [
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY n + (objects.payload.score + 1) DESC NULLS LAST",
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 ORDER BY COUNT(*) + (`objects`.`payload`.`score` + 1)",
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY n + (payload.score + 1)",
      "SELECT payload.score + 1 AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 ORDER BY payload + 1",
      "SELECT DISTINCT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY n + (objects.payload.score + 1)",
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY payload.score + 1 ORDER BY n + (objects.payload.score + 1)",
      "SELECT payload.score + 1 AS first, payload.score + 1 AS second, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY n + (objects.payload.score + 1)",
    ] {
    let body = semantic(checked_group_property(source))
    assert_eq(body.split("\"property\":").length() - 1, 1, msg=source)
  }
}

///|
test "ORDER grouped subexpressions distinguish output object receivers" {
  let context = {
    ..group_property_context(),
    parameter_declarations: Some(having_object_declarations()),
  }
  for
    (order, property_count) in [
      ("payload.score + 1", 2),
      ("objects.payload.score + 1", 1),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT payload.score + 1 AS bucket, @assessment AS payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 ORDER BY " +
        order +
        ", bucket",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(having_object_values()),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("ORDER uses the checked nullable object alias")
    }
    let body = semantic(actual)
    assert_eq(
      body.split("\"property\":").length() - 1,
      property_count,
      msg=order,
    )
    assert_eq(body.split("\"$param\":").length() - 1, 1)
  }
}

///|
test "ORDER grouped subexpressions retain JOIN and CTE input scope" {
  for
    source in [
      "SELECT l.x + 1 AS bucket, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x GROUP BY l.x + 1 ORDER BY n + (l.x + 1)",
      "WITH summarized AS (SELECT x + 1 AS bucket, COUNT(*) AS n FROM t GROUP BY x + 1 ORDER BY n + (t.x + 1)) SELECT bucket, n FROM summarized ORDER BY bucket",
      "SELECT x + 1 AS bucket, COUNT(*) AS n FROM t GROUP BY x + 1 ORDER BY n + (t.x + 1) |> WHERE n > 0 |> ORDER BY bucket",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
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
      _ => fail("ORDER retains evaluated JOIN and CTE keys: " + source)
    }
  }
}

///|
test "ORDER grouped subexpressions cannot restore dropped keys or an earlier scope" {
  for
    source in [
      "SELECT DISTINCT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY objects.payload.score + 1",
      "SELECT DISTINCT -id AS id, COUNT(*) AS n FROM objects GROUP BY objects.id ORDER BY objects.id + 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(UnsupportedOrdering),
      msg=source,
    )
  }
  for
    source in [
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY payload.score",
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY other.score + 1",
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY payload.score + 2",
      "SELECT COUNT(*) AS n FROM objects AS current GROUP BY current.payload.score + 1 ORDER BY old.payload.score + 1",
      "SELECT payload.score + 1 AS bucket, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY bucket |> ORDER BY objects.payload.score + 1",
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
test "ORDER grouped subexpressions preserve bounded work and original origins" {
  let query = @query.parse_query(
    "SELECT x + 1 AS bucket, COUNT(*) AS n FROM pair GROUP BY x + 1 ORDER BY n + (pair.x + 1)",
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
test "ORDER grouped subexpressions recognize implicit property aliases" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"score":2,"payload":{"score":10}},{"score":1,"payload":{"score":20}}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..group_property_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["score", "payload"],
        graph_bindings: [],
      },
    ],
  }
  let program = compile(
    @query.parse_query(
      "SELECT (payload).score, COUNT(*) AS n FROM objects GROUP BY (payload).score, score + 1 ORDER BY score + 1",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  // Input score=2,1 would reverse output score=10,20. ORDER must add to the
  // evaluated implicit output alias, not use the other computed GROUP key.
  assert_true(
    semantic(program).contains(
      "\"aql_query_sort_5\":{\"add\":[{\"field\":\"aql_group_key_0\"},{\"literal\":1}]}",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the implicit output alias retains its checked numeric value")
  }
}
