///|
test "QUALIFY window alias matches an independent analytic filter Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"n":{"fn":"row_number"}}}},{"filter":{"lte":[{"field":"n"},{"literal":1}]}},{"select":["x","n"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent analytic filter Program is closed")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT x, ROW_NUMBER() OVER (ORDER BY y) AS n FROM t QUALIFY n <= 1 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "QUALIFY resolves SELECT aliases before inputs and preserves qualification" {
  let aliases = checked_join_order(
    "SELECT x, ROW_NUMBER() OVER (ORDER BY x) AS y FROM t QUALIFY y = 1 ORDER BY x",
  )
  assert_true(
    aliases.contains(
      "\"filter\":{\"eq\":[{\"field\":\"aql_analytic_output_2\"},{\"literal\":1}]}",
    ),
  )
  let inputs = checked_join_order(
    "SELECT x, ROW_NUMBER() OVER (ORDER BY x) AS y FROM t QUALIFY t.y = 10 ORDER BY x",
  )
  assert_true(
    inputs.contains("\"filter\":{\"eq\":[{\"field\":\"y\"},{\"literal\":10}]}"),
  )
}

///|
test "QUALIFY shares evaluated scalar aliases with the final SELECT" {
  let text = checked_join_order(
    "SELECT x + 1 AS y, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t QUALIFY y > 2 ORDER BY y",
  )
  assert_eq(text.split("\"add\":").length() - 1, 1)
  assert_true(
    text.contains(
      "\"filter\":{\"gt\":[{\"field\":\"aql_qualify_expr_3\"},{\"literal\":2}]}",
    ),
  )
  assert_true(text.contains("{\"y\":\"aql_qualify_expr_3\"}"))
}

///|
test "QUALIFY qualified input ranges do not demand colliding SELECT aliases" {
  let text = checked_join_order(
    "SELECT 1 / (x - 1) AS t, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t QUALIFY t.x > 1 ORDER BY n",
  )
  let filters = text.split("\"filter\":").collect()
  let divisions = text.split("\"divide\":").collect()
  assert_eq(filters.length(), 2)
  assert_eq(divisions.length(), 2)
  let filter = filters[0].length()
  let divide = divisions[0].length()
  assert_true(filter < divide)
}

///|
test "QUALIFY qualified nullable object paths do not demand colliding SELECT aliases" {
  let program = compile(
    @query.parse_query(
      "SELECT 1 / (id - 1) AS objects, ROW_NUMBER() OVER (ORDER BY id) AS n FROM objects QUALIFY objects.id > 1 AND objects.payload.score > 5 ORDER BY n",
      syntax_limits(),
    ).unwrap(),
    analytic_property_context(),
    construction_limits(),
  ).unwrap()
  let text = semantic(program)
  let filters = text.split("\"filter\":").collect()
  let divisions = text.split("\"divide\":").collect()
  assert_eq(filters.length(), 2)
  assert_eq(divisions.length(), 2)
  assert_true(filters[0].length() < divisions[0].length())
}

///|
test "QUALIFY hidden calls grouping and composed scopes reach the common checker" {
  for
    source in [
      "SELECT x FROM t QUALIFY ROW_NUMBER() OVER (ORDER BY y) = 1 ORDER BY x", "SELECT DISTINCT x FROM t QUALIFY ROW_NUMBER() OVER (ORDER BY x) <= 2 ORDER BY x LIMIT 1",
      "SELECT x, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t QUALIFY n > 0 AND CAST(NULL AS BOOL)",
      "SELECT x, COUNT(*) AS total, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t GROUP BY x HAVING total > 0 QUALIFY n = 1 AND COUNT(*) > 0 ORDER BY x",
      "SELECT l.x, ROW_NUMBER() OVER (ORDER BY l.x) AS n FROM t AS l JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 QUALIFY n = 1 ORDER BY x",
      "WITH chosen AS (SELECT x FROM t QUALIFY ROW_NUMBER() OVER (ORDER BY y) = 1) SELECT x FROM chosen ORDER BY x",
    ] {
    let generated = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        generated,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("QUALIFY uses ordinary closed inputs: " + source)
    }
  }
}

///|
test "QUALIFY refuses missing windows and unbound names at the intended boundary" {
  assert_true(
    @query.parse_query("SELECT x FROM t QUALIFY x > 0", syntax_limits())
    is Err({ issue: @query.Syntax("QUALIFY requires a window function"), .. }),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT x, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t QUALIFY missing > 0",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "QUALIFY scalar slot reuse expires before a later Pipe input scope" {
  let text = checked_join_order(
    "SELECT x + 1 AS x, ROW_NUMBER() OVER (ORDER BY x) AS n FROM t QUALIFY x > 1 |> SET x = -x |> SELECT x + 1 AS y |> ORDER BY y",
  )
  assert_eq(text.split("\"add\":").length() - 1, 2)
  assert_true(
    text.contains("\"add\":[{\"field\":\"aql_pipe_set_2\"},{\"literal\":1}]"),
  )
}
