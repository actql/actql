///|
test "quoted QUALIFY window calls match an independent hidden-analytic Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"aql_qualify_call_0":{"fn":"row_number"}}}},{"filter":{"lte":[{"field":"aql_qualify_call_0"},{"literal":1}]}},{"select":["x"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent hidden analytic Program must be closed")
  }
  assert_eq(
    checked_join_order(
      "SELECT x FROM t QUALIFY ROW_NUMBER() OVER (ORDER BY y) <= 1 ORDER BY x",
    ),
    semantic(expected),
  )
  for
    source in [
      "SELECT x FROM t QUALIFY `ROW_NUMBER`() OVER (ORDER BY y) <= 1 ORDER BY x",
      "SELECT x FROM t QUALIFY `rOw_NuMbEr`() OVER (ORDER BY y) <= 1 ORDER BY x",
      "SELECT x FROM t QUALIFY `\\x52OW_NUMBER`() OVER (ORDER BY y) <= 1 ORDER BY x",
    ] {
    let parsed = match @query.parse_query(source, syntax_limits()) {
      Ok(query) => query
      Err({ issue: @query.Syntax(message), .. }) =>
        fail(source + ": " + message)
      Err(_) => fail("unexpected lexical/expression limit: " + source)
    }
    let actual = compile(parsed, join_order_context(), construction_limits()).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("hidden analytic source must not acquire new inputs")
    }
  }
}

///|
test "quoted QUALIFY calls retain the common unsupported-signature boundary" {
  for
    source in [
      "SELECT x FROM t QUALIFY `RANK`(x) OVER (ORDER BY y) <= 1", "SELECT x FROM t QUALIFY `ROW_NUMBER`(x) OVER (ORDER BY y) <= 1",
      "SELECT x FROM t QUALIFY `LAG`(x, 1, 2) OVER (ORDER BY y) IS NOT NULL",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
    )
  }
}
