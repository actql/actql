///|
test "SQL grouped subexpressions reuse an evaluated key in an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_query_expr_0":{"add":[{"field":"aql_select_aggregate_0"},{"field":"aql_group_key_0"}]}}},{"select":[{"n":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ordinary group and derive admit the independent evaluated key")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT COUNT(*) + (pair.x + 1) AS n FROM pair GROUP BY x + 1",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "SQL grouped subexpressions preserve property receivers and output collisions" {
  for
    source in [
      "SELECT COUNT(*) + payload.score AS n FROM objects GROUP BY payload.score",
      "SELECT COUNT(*) + (payload.score + 1) AS n FROM objects GROUP BY payload.score + 1 HAVING n > 11",
      "SELECT COUNT(*) + objects.payload.score AS n FROM objects GROUP BY payload.score",
      "SELECT COUNT(*) + (payload.score + 1) AS n FROM objects GROUP BY objects.payload.score + 1",
      "SELECT COUNT(*) + (`objects`.`payload`.`score` + 1) AS n FROM objects GROUP BY payload.score + 1",
      "SELECT payload.score + 1 AS payload, COUNT(*) + (objects.payload.score + 1) AS n FROM objects GROUP BY objects.payload.score + 1 ORDER BY payload",
      "SELECT payload.score AS other, COUNT(*) + objects.payload.score AS n FROM objects GROUP BY payload.score",
      "SELECT COUNT(*) + (payload.score + 1) + (objects.payload.score + 1) AS n FROM objects GROUP BY payload.score + 1",
      "SELECT COUNT(*) + (payload.score + 1) AS n FROM objects WHERE FALSE GROUP BY payload.score + 1",
    ] {
    let body = semantic(checked_group_property(source))
    assert_eq(
      body.split("\"property\":").length(),
      2,
      msg="the grouped receiver is projected once, before GROUP: " + source,
    )
  }
}

///|
test "SQL grouped subexpressions keep ungrouped and sibling scope refusals" {
  for
    source in [
      "SELECT COUNT(*) + objects.other.score AS n FROM objects GROUP BY payload.score",
      "SELECT COUNT(*) + payload.score AS n FROM objects GROUP BY payload.score + 1",
      "SELECT COUNT(*) + (payload.score + 2) AS n FROM objects GROUP BY payload.score + 1",
      "SELECT payload.score + 1 AS bucket, COUNT(*) + bucket AS n FROM objects GROUP BY payload.score + 1",
      "SELECT COUNT(*) + old.payload.score AS n FROM objects AS `current` GROUP BY current.payload.score",
      "SELECT COUNT(*) + aql_pipe_group_bound_0 AS n FROM objects GROUP BY payload.score",
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
test "SQL grouped subexpressions retain CTE and JOIN input bindings" {
  for
    source in [
      "WITH summarized AS (SELECT COUNT(*) + (x + 1) AS n FROM t GROUP BY x + 1) SELECT n FROM summarized ORDER BY n",
      "SELECT COUNT(*) + (l.x + 1) AS n FROM t AS l JOIN t AS r ON l.x = r.x GROUP BY l.x + 1 ORDER BY n",
      "SELECT COUNT(*) + (x + 1) AS n FROM t GROUP BY t.x + 1 |> WHERE n > 0 |> ORDER BY n",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    let program = match program {
      Ok(program) => program
      Err(UnknownColumn) => fail(source + ": UnknownColumn")
      Err(AmbiguousColumn) => fail(source + ": AmbiguousColumn")
      Err(UnknownRelation) => fail(source + ": UnknownRelation")
      Err(AmbiguousRelation) => fail(source + ": AmbiguousRelation")
      Err(UnsupportedJoin) => fail(source + ": UnsupportedJoin")
      Err(UnsupportedOrdering) => fail(source + ": UnsupportedOrdering")
      Err(UnsupportedCte) => fail(source + ": UnsupportedCte")
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        fail(
          source +
          ": UnknownReference at " +
          @origin.start(origin).byte_offset.to_string(),
        )
      Err(_) => fail(source + ": another grouped scalar rejection")
    }
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ =>
        fail(
          "the existing CTE/JOIN owners receive the evaluated key: " + source,
        )
    }
  }
}

///|
test "SQL grouped subexpressions preserve original error locations under work limits" {
  let query = @query.parse_query(
    "SELECT COUNT(*) + (pair.x + 1) AS n FROM pair GROUP BY x + 1",
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
