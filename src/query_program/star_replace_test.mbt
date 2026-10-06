///|
test "star REPLACE swaps original columns through an independent checked projection" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","select":[{"x":"y"},{"y":"x"}]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent swap Program is closed")
  }
  for
    source in [
      "SELECT * REPLACE (y AS x, x AS y) FROM t ORDER BY x", "FROM t |> SELECT * REPLACE (y AS x, x AS y) |> ORDER BY x",
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
test "star REPLACE uses existing GROUP HAVING analytic and JOIN scopes" {
  for
    source in [
      "SELECT * REPLACE (y + 1 AS x) FROM t GROUP BY 1, y HAVING x > 0 ORDER BY x",
      "SELECT * REPLACE (SUM(x) AS x) FROM t GROUP BY y ORDER BY y", "SELECT * REPLACE (COUNT(* WHERE y > 10) AS x) FROM t GROUP BY y HAVING x >= 0 ORDER BY x",
      "SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY y) AS x) FROM t ORDER BY x",
      "SELECT l.* REPLACE (l.x + r.k AS x) FROM t AS l JOIN r ON l.x = r.k ORDER BY x",
      "WITH chosen AS (SELECT x, y FROM t) SELECT * REPLACE (-x AS x) FROM chosen ORDER BY -x",
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
      _ => fail("replacements use the common checker: " + source)
    }
  }
}

///|
test "star REPLACE validates retained targets and original-snapshot references" {
  for
    source in [
      "SELECT * REPLACE (1 AS absent) FROM t", "SELECT * EXCEPT (x) REPLACE (1 AS x) FROM t",
      "FROM t |> DROP x |> SELECT * REPLACE (1 AS x)", "FROM t |> RENAME x AS renamed |> SELECT * REPLACE (1 AS x)",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=source,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * REPLACE (1 AS x, 2 AS `X`) FROM t",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  assert_true(
    compile(
      @query.parse_query(
        "FROM t AS old |> AS current |> SELECT * REPLACE (old.x AS x)",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}
