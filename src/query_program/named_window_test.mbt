///|
test "named WINDOW matches an independently checked analytic Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"n":{"fn":"row_number"}}}},{"select":["x","n"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent analytic Program has closed Values inputs")
  }
  for
    source in [
      "SELECT x, ROW_NUMBER() OVER w AS n FROM t WINDOW w AS (ORDER BY y) ORDER BY x",
      "SELECT x, ROW_NUMBER() OVER (`W`) AS n FROM t WINDOW w AS (ORDER BY y) ORDER BY x",
      "SELECT x, ROW_NUMBER() OVER final AS n FROM t WINDOW base AS (), ordered AS (base ORDER BY y), final AS ordered ORDER BY x",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "named WINDOW operation snapshots cannot mutate the parsed specification" {
  let parsed = @query.parse_query(
    "SELECT x, ROW_NUMBER() OVER w AS n FROM t WINDOW w AS (ORDER BY y)",
    syntax_limits(),
  ).unwrap()
  guard @query.operation_at(parsed, 0) is Some(Analytic(projections)) else {
    fail("analytic operation")
  }
  projections[1].analytic.unwrap().window.order_by.clear()
  guard @query.operation_at(parsed, 0) is Some(Analytic(retained)) else {
    fail("retained analytic operation")
  }
  assert_eq(retained[1].analytic.unwrap().window.order_by.length(), 1)
}

///|
test "named WINDOW inherits checked partitions frames and QUALIFY slots" {
  for
    source in [
      "SELECT x, ROW_NUMBER() OVER w AS n FROM t WINDOW w AS (PARTITION BY x ORDER BY y) ORDER BY x",
      "SELECT x, COUNT(*) OVER (ordered ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM t WINDOW base AS (PARTITION BY x), ordered AS (base ORDER BY y) ORDER BY x",
      "SELECT x, COUNT(*) OVER final AS n FROM t WINDOW ordered AS (ORDER BY y), framed AS (ordered ROWS BETWEEN CURRENT ROW AND CURRENT ROW), final AS framed ORDER BY x",
      "SELECT x FROM t QUALIFY ROW_NUMBER() OVER w = 1 WINDOW w AS (ORDER BY y) ORDER BY x",
      "SELECT x, ROW_NUMBER() OVER w AS y FROM t QUALIFY y = 1 WINDOW w AS (ORDER BY t.y) ORDER BY x",
      "SELECT * REPLACE (ROW_NUMBER() OVER w AS x) FROM t WINDOW w AS (ORDER BY y) ORDER BY x",
      "WITH chosen AS (SELECT x FROM t QUALIFY ROW_NUMBER() OVER w = 1 WINDOW w AS (ORDER BY y)) SELECT x FROM chosen ORDER BY x",
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
      _ => fail("named windows preserve ordinary closed inputs: " + source)
    }
  }
}

///|
test "named WINDOW rejects name and clause conflicts without scope fallback" {
  for
    (source, reason) in [
      ("SELECT ROW_NUMBER() OVER missing AS n FROM t", "Unknown named window"),
      (
        "SELECT ROW_NUMBER() OVER w AS n FROM t WINDOW w AS later, later AS (ORDER BY x)",
        "Unknown named window",
      ),
      (
        "SELECT ROW_NUMBER() OVER w AS n FROM t WINDOW w AS w", "Unknown named window",
      ),
      (
        "SELECT ROW_NUMBER() OVER w AS n FROM t WINDOW w AS (ORDER BY x), `W` AS (ORDER BY y)",
        "Duplicate named window",
      ),
      (
        "SELECT ROW_NUMBER() OVER (w ORDER BY y) AS n FROM t WINDOW w AS (ORDER BY x)",
        "Duplicate named window ORDER BY",
      ),
      (
        "SELECT ROW_NUMBER() OVER (w PARTITION BY x) AS n FROM t WINDOW w AS (ORDER BY x)",
        "Named window cannot be combined with PARTITION BY",
      ),
      (
        "SELECT COUNT(*) OVER (w ORDER BY x) AS n FROM t WINDOW w AS (ROWS BETWEEN CURRENT ROW AND CURRENT ROW)",
        "Cannot extend a framed named window",
      ),
      (
        "SELECT COUNT(*) OVER (w ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM t WINDOW w AS (ORDER BY x ROWS BETWEEN CURRENT ROW AND CURRENT ROW)",
        "Cannot extend a framed named window",
      ),
      (
        "WITH chosen AS (SELECT ROW_NUMBER() OVER w AS n FROM t WINDOW w AS (ORDER BY x)) SELECT ROW_NUMBER() OVER w AS n FROM chosen",
        "Unknown named window",
      ),
    ] {
    assert_true(
      @query.parse_query(source, syntax_limits())
      is Err({ issue: @query.Syntax(message), .. }) &&
      message == reason,
      msg=source,
    )
  }
}
