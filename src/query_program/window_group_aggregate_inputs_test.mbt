///|
fn window_group_aggregate_expected() -> @program.Program {
  // Counts are 2 for x=1 and 1 for x=2. Descending count deliberately ranks
  // x=1 first, independently of input enumeration and descending key order.
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    qualify_group_collision_seed() +
    (
      #|,{"from":"t","group":{"by":["x"],"aggregates":{"aql_select_aggregate_1":{"fn":"count"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"aql_select_aggregate_1","dir":"desc","nulls":"last"},{"field":"x","dir":"asc","nulls":"first"}],"functions":{"rn":{"fn":"row_number"}}}},{"select":["x","rn"]},{"sort":[{"field":"rn","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","rn"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent aggregate window input Program passes the ordinary checker" {
  match
    @check.check_parsed(
      window_group_aggregate_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent grouped window input must check")
  }
}

///|
test "SELECT OVER aggregate key matches the independent complete Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT t.x, ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, t.x) AS rn FROM t GROUP BY t.x ORDER BY rn",
      syntax_limits(),
    ).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(window_group_aggregate_expected()))
}

///|
fn checked_window_group_input(text : String) -> String raise {
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    qualify_group_collision_context(),
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
    _ => fail("grouped window input must check: " + text)
  }
  semantic(actual)
}

///|
test "inline window aggregate keys compose in SELECT QUALIFY and query ORDER" {
  for
    text in [
      "SELECT t.x, ROW_NUMBER() OVER (ORDER BY COUNT(t.y) + 1 DESC, t.x) AS rn FROM t GROUP BY t.x ORDER BY rn",
      "SELECT t.x, ROW_NUMBER() OVER (PARTITION BY COUNT(*) ORDER BY t.x) AS rn FROM t GROUP BY t.x ORDER BY t.x",
      "SELECT t.x, ROW_NUMBER() OVER (ORDER BY SUM(t.y) DESC, t.x) AS rn FROM t GROUP BY t.x ORDER BY rn",
      "SELECT t.x FROM t GROUP BY t.x QUALIFY ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, t.x) = 1 ORDER BY t.x",
      "SELECT t.x FROM t GROUP BY t.x ORDER BY ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, t.x)",
      "SELECT ROW_NUMBER() OVER (ORDER BY COUNT(*)) AS rn FROM t",
    ] {
    ignore(checked_window_group_input(text))
  }
}

///|
test "window aggregate keys reuse evaluated GROUP slots and exclude SELECT siblings" {
  let actual = checked_window_group_input(
    "SELECT t.x, COUNT(*) AS total, ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, t.x) AS rn FROM t GROUP BY t.x ORDER BY rn",
  )
  assert_eq(actual.split("\"fn\":\"count\"").length(), 2)
  assert_true(actual.contains("\"field\":\"total\""))
  assert_true(
    compile(
      @query.parse_query(
        "SELECT t.x AS invented, ROW_NUMBER() OVER (ORDER BY COUNT(invented), t.x) AS rn FROM t GROUP BY t.x",
        syntax_limits(),
      ).unwrap(),
      qualify_group_collision_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "aggregate window keys do not admit nested windows or implicit Pipe grouping" {
  for
    text in [
      "SELECT t.x, ROW_NUMBER() OVER (ORDER BY COUNT(*) OVER (ORDER BY t.x)) AS rn FROM t GROUP BY t.x",
      "FROM t |> SELECT t.x, ROW_NUMBER() OVER (ORDER BY COUNT(*), t.x) AS rn",
    ] {
    assert_true(
      @query.parse_query(text, syntax_limits())
      is Err({ issue: @query.Syntax(_), .. }),
      msg=text,
    )
  }
}

///|
test "query ORDER window aggregate arguments retain SELECT alias ownership" {
  // SUM(y) in query ORDER consumes -t.y, so original y ranks 21,20,10.
  // Resolving it to the input y would instead rank 10,20,21.
  let actual = checked_window_group_input(
    "SELECT t.y AS original, -t.y AS y FROM t GROUP BY t.y ORDER BY ROW_NUMBER() OVER (ORDER BY SUM(y), original)",
  )
  assert_true(actual.contains("\"aql_having_argument_"), msg=actual)
  assert_true(actual.contains("\"negate\":{\"field\":\"y\"}"), msg=actual)
  assert_false(actual.contains("\"field\":\"y\",\"fn\":\"sum\""), msg=actual)
}
