///|
fn named_window_aggregate_expected() -> @program.Program {
  // Independent GROUP -> ANALYTIC: x=1 has two rows, x=2 has one.
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    qualify_group_collision_seed() +
    (
      #|,{"from":"t","group":{"by":["x"],"aggregates":{"aql_window_aggregate_0":{"fn":"count"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"aql_window_aggregate_0","dir":"desc","nulls":"last"},{"field":"x","dir":"asc","nulls":"first"}],"functions":{"rn":{"fn":"row_number"}}}},{"select":["x","rn"]},{"sort":[{"field":"rn","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","rn"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent named window aggregate key Program passes the normal checker" {
  match
    @check.check_parsed(
      named_window_aggregate_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent named window aggregate key must check")
  }
}

///|
test "named window aggregate key matches an independently authored complete Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT t.x, ROW_NUMBER() OVER w AS rn FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(*) DESC, t.x) ORDER BY rn",
      syntax_limits(),
    ).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(named_window_aggregate_expected()))
}

///|
test "named window aggregate keys create the existing implicit global SQL group" {
  ignore(
    checked_window_group_input(
      "SELECT ROW_NUMBER() OVER w AS rn FROM t WINDOW w AS (ORDER BY COUNT(*))",
    ),
  )
}

///|
test "named aggregate windows compose through inheritance QUALIFY and SQL grouping" {
  for
    source in [
      "SELECT t.x, ROW_NUMBER() OVER final AS rn FROM t GROUP BY t.x WINDOW base AS (PARTITION BY COUNT(*)), ordered AS (base ORDER BY t.x), final AS ordered ORDER BY t.x",
      "SELECT t.x FROM t GROUP BY t.x QUALIFY ROW_NUMBER() OVER w = 1 WINDOW w AS (ORDER BY SUM(t.y) DESC, t.x) ORDER BY t.x",
      "SELECT t.x, ROW_NUMBER() OVER w AS rn FROM t GROUP BY ALL WINDOW w AS (ORDER BY COUNT(*) DESC, t.x) ORDER BY rn",
      "SELECT COUNT(*) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rn FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(*) DESC, t.x) ORDER BY rn",
      "SELECT t.x, ROW_NUMBER() OVER (`W`) AS rn FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(t.y) + 1 DESC, t.x) ORDER BY rn",
      "SELECT t.x, LAG(COUNT(*)) OVER w AS value FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(*) DESC, t.x) ORDER BY t.x",
      "SELECT t.x, SUM(SUM(t.y)) OVER w AS value FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(*) DESC, t.x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) ORDER BY t.x",
    ] {
    ignore(checked_window_group_input(source))
  }
}

///|
test "named window aggregate slots are shared without changing declaration input scope" {
  let actual = checked_window_group_input(
    "SELECT t.x AS original, COUNT(*) AS x, ROW_NUMBER() OVER w AS rn, RANK() OVER other AS rank FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(*) DESC, t.x), other AS (ORDER BY COUNT(*) DESC, t.x) ORDER BY rn",
  )
  assert_eq(actual.split("\"fn\":\"count\"").length(), 2)
  assert_true(
    compile(
      @query.parse_query(
        "SELECT t.x AS invented, ROW_NUMBER() OVER w AS rn FROM t GROUP BY t.x WINDOW w AS (ORDER BY COUNT(invented), t.x)",
        syntax_limits(),
      ).unwrap(),
      qualify_group_collision_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "unused named window aggregate definitions add no GROUP or failing computation" {
  for
    source in [
      "SELECT t.x, ROW_NUMBER() OVER w AS rn FROM t WINDOW unused AS (ORDER BY COUNT(*)), w AS (ORDER BY t.x) ORDER BY rn",
      "SELECT t.x, ROW_NUMBER() OVER w AS rn FROM t WINDOW unused AS (ORDER BY SUM(1 / 0)), w AS (ORDER BY t.x) ORDER BY rn",
    ] {
    let actual = checked_window_group_input(source)
    assert_false(actual.contains("\"group\":"), msg=actual)
    assert_false(actual.contains("\"divide\":"), msg=actual)
  }
}

///|
test "named window implicit grouping precedes a nonaggregate HAVING predicate" {
  ignore(
    checked_window_group_input(
      "SELECT ROW_NUMBER() OVER w AS rn FROM t HAVING TRUE WINDOW w AS (ORDER BY COUNT(*))",
    ),
  )
  for
    source in [
      "SELECT ROW_NUMBER() OVER w AS rn FROM t HAVING TRUE WINDOW w AS (ORDER BY t.x)",
      "SELECT ROW_NUMBER() OVER w AS rn FROM t HAVING TRUE WINDOW unused AS (ORDER BY COUNT(*)), w AS (ORDER BY t.x)",
    ] {
    assert_true(
      @query.parse_query(source, syntax_limits())
      is Err({ issue: @query.Syntax("HAVING requires grouping"), .. }),
      msg=source,
    )
  }
}
