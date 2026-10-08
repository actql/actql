///|
test "GROUP BY ALL infers input keys into an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"select":["x","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the ordinary group owner admits the independent Program")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT x, COUNT(*) AS n FROM t GROUP BY ALL",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "GROUP BY ALL never resolves inferred input keys through SELECT aliases" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x","y"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"y":"x"},{"z":"y"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["y","z","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT x AS y, y AS z, COUNT(*) AS n FROM t GROUP BY ALL", "SELECT t.x AS y, t.y AS z, COUNT(*) AS n FROM t GROUP BY ALL",
      "SELECT `t`.`x` AS y, `t`.`y` AS z, COUNT(*) AS n FROM t GROUP BY ALL",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "GROUP BY ALL excludes constants and aggregates including embedded atoms" {
  for
    source in [
      "SELECT COUNT(*) AS n, 1 AS one FROM t GROUP BY ALL", "SELECT COUNT(*) AS n, 1 AS one FROM t WHERE FALSE GROUP BY ALL",
      "SELECT 1 AS one FROM t GROUP BY ALL", "SELECT 1 AS one GROUP BY ALL", "SELECT x, COUNT(*) + x AS n FROM t GROUP BY ALL",
      "SELECT SUM(y) AS x, x AS original FROM t GROUP BY ALL",
    ] {
    let actual = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
      Err(Expression({ issue: UnknownReference, .. })) =>
        fail(source + ": UnknownReference")
      Err(_) => fail(source + ": another lowering failure")
    }
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      )
      is Checked(_),
      msg=source,
    )
    if source.contains("1 AS one") {
      assert_true(semantic(actual).contains("\"by\":[]"), msg=source)
    } else {
      assert_true(semantic(actual).contains("\"by\":[\"x\"]"), msg=source)
    }
  }
}

///|
test "GROUP BY ALL uses shortest input paths before computed expressions" {
  for
    source in [
      "SELECT x + 1 AS next, x, COUNT(*) AS n FROM t GROUP BY ALL", "SELECT t.x + 1 AS next, x, COUNT(*) AS n FROM t GROUP BY ALL",
      "SELECT x, y, [t.x, y] AS coordinates FROM t GROUP BY ALL", "SELECT * EXCEPT (y), COUNT(*) AS n FROM t GROUP BY ALL",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_true(
      body.contains(
        if source.contains("coordinates") {
          "\"by\":[\"x\",\"y\"]"
        } else {
          "\"by\":[\"x\"]"
        },
      ),
      msg=source,
    )
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
}

///|
test "GROUP BY ALL computed keys do not supply prefixes for other computed keys" {
  let actual = compile(
    @query.parse_query(
      "SELECT x + 1 AS next, x + 2 AS later, COUNT(*) AS n FROM t GROUP BY ALL",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(actual).contains(
      "\"by\":[\"aql_group_key_0\",\"aql_group_key_1\"]",
    ),
  )
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "GROUP BY ALL preserves property input meaning and evaluated key reuse" {
  let expected = semantic(independent_group_property_program())
  for
    source in [
      "SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY ALL", "SELECT objects.payload.SCORE AS score, COUNT(*) AS n FROM objects GROUP BY ALL",
      "SELECT (objects.payload).score AS score, COUNT(*) AS n FROM objects GROUP BY ALL",
    ] {
    assert_eq(semantic(checked_group_property(source)), expected, msg=source)
  }
  for
    source in [
      "SELECT payload.score + 1 AS next, objects.payload.score AS score, COUNT(*) AS n FROM objects GROUP BY ALL",
      "SELECT (payload).score + 1 AS next, objects.payload.score AS score, COUNT(*) AS n FROM objects GROUP BY ALL",
      "SELECT objects.payload.score + 1 AS next, (payload).score AS score, COUNT(*) AS n FROM objects GROUP BY ALL",
    ] {
    let body = semantic(checked_group_property(source))
    assert_eq(body.split("\"property\":").length(), 2, msg=source)
    assert_true(body.contains("\"by\":[\"aql_group_key_0\"]"), msg=source)
  }
}

///|
test "GROUP BY ALL preserves CTE JOIN and SELECT-headed Pipe composition" {
  for
    source in [
      "WITH chosen AS (SELECT x FROM t) SELECT x, COUNT(*) AS n FROM chosen GROUP BY ALL ORDER BY x",
      "SELECT l.x AS x, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x GROUP BY ALL ORDER BY x",
      "SELECT x, COUNT(*) AS n FROM t GROUP BY ALL |> WHERE n > 0 |> ORDER BY x",
      "SELECT x, COUNT(*) AS n FROM t GROUP BY ALL ORDER BY ROW_NUMBER() OVER (ORDER BY n DESC, x)",
      "SELECT x, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t GROUP BY ALL ORDER BY x",
      "SELECT x, ROW_NUMBER() OVER (ORDER BY x) + 1 AS n FROM t GROUP BY ALL ORDER BY x",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
}

///|
test "GROUP BY ALL retains unknown input and inference work refusals" {
  for
    source in [
      "SELECT missing FROM t GROUP BY ALL", "SELECT SUM(x) AS n, n + 1 AS later FROM t GROUP BY ALL",
      "SELECT old.x FROM t AS current GROUP BY ALL",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT x, y, x + y AS total FROM t GROUP BY ALL",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}

///|
test "GROUP alias collisions retain separate input and aggregate slots" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"aql_select_aggregate_6":{"fn":"count"}}}},{"select":[{"x":"aql_select_aggregate_6"},{"original":"x"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","original"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT COUNT(*) AS x, x AS original FROM t GROUP BY ALL", "SELECT COUNT(*) AS x, x AS original FROM t GROUP BY t.x",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
  for
    source in [
      "SELECT COUNT(*) AS x, x AS original FROM t GROUP BY ALL HAVING x > 0 ORDER BY original",
      "SELECT COUNT(*) AS x, x AS original FROM t GROUP BY t.x HAVING X > 0 ORDER BY x, original",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
}
