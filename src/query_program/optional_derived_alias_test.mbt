///|
test "optional derived alias has an independent existing Program control" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.optional_derived_alias","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":true}},"rows":[{"id":1},{"id":null},{"id":2},{"id":1}]},"as":"rows"},{"from":"rows","filter":{"not":{"is_null":{"field":"id"}}}},{"sort":[{"field":"id","dir":"desc","nulls":"first"}]},{"take":3},{"select":["id"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed independent control")
  }
}

///|
test "unnamed derived table preserves NULL predicate duplicates and explicit ordering" {
  let query = match
    @query.parse_query(
      "SELECT id FROM (SELECT id FROM UNNEST([1,CAST(NULL AS FLOAT64),2,1]) AS id) WHERE id IS NOT NULL ORDER BY id DESC NULLS FIRST LIMIT 3",
      syntax_limits(),
    ) {
    Ok(q) => q
    Err({ issue: @query.Syntax(reason), .. }) =>
      fail("unaliased derived source: " + reason)
    Err(_) => fail("unexpected parse error")
  }
  let actual = compile(
    query,
    { ..values_context(), inputs: [], },
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
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed unaliased source")
  }
}

///|
test "unaliased table preserves its inner Pipe ranges and value receiver" {
  for
    source in [
      "SELECT r.x AS original,x AS `current`,y FROM (FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10) ORDER BY original",
      "SELECT r.x AS original,x AS `current` FROM (FROM t |> AS r |> SET x=x+10) ORDER BY original",
      "FROM (FROM t |> AS r |> SET x=x+10) |> WHERE r.x > 0 |> SELECT r.x AS original,x AS `current` |> ORDER BY original",
      "SELECT current.x,current.y FROM (FROM t |> AS r |> SET x=x+10) AS `current` ORDER BY current.x",
      "SELECT element AS value FROM (FROM UNNEST([1,2]) AS element) ORDER BY value",
    ] {
    let query = match @query.parse_query(source, syntax_limits()) {
      Ok(q) => q
      Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
      Err(_) => fail("parse error")
    }
    let actual = match
      compile(query, join_order_context(), construction_limits()) {
      Ok(p) => p
      Err(_) => fail(source + ": lowering refusal")
    }
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed preserved scope")
    }
  }
}

///|
test "unaliased projected or set outputs do not restore discarded ranges" {
  for
    source in [
      "SELECT r.x FROM (FROM t |> AS r |> SELECT x)", "SELECT r.x FROM (FROM t |> AS r |> SET x=x+10) `current`",
      "SELECT t.x FROM (FROM t |> UNION ALL (FROM t))",
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    assert_true(
      result is Err(UnknownColumn) ||
      result is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
  let program = compile(
    @query.parse_query(
      "SELECT x FROM (FROM t |> UNION ALL (FROM t)) ORDER BY x",
      syntax_limits(),
    ).unwrap(),
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
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed unnamed set source")
  }
}

///|
test "unnamed derived table preserves ranges across transparent parentheses" {
  let q = @query.parse_query(
    "SELECT r.x AS original FROM ((FROM t |> AS r)) ORDER BY original",
    syntax_limits(),
  ).unwrap()
  let p = match compile(q, join_order_context(), construction_limits()) {
    Ok(p) => p
    Err(_) => fail("transparent parentheses lost the range")
  }
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed parenthesized range")
  }
}

///|
test "unnamed projected sources match the independent established producer Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.sql_set","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"a":{"type":"number","nullable":true},"b":{"type":"string","nullable":false}},"rows":[{"a":1,"b":"x"},{"a":1,"b":"x"},{"a":2,"b":"y"},{"a":null,"b":"n"}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","filter":{"gt":[{"field":"a"},{"literal":0}]}},{"select":["a","b"],"as":"aql_script_cte_2"},{"from":"aql_script_cte_2","select":["b","a"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["b","a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT b,a FROM (SELECT a,b FROM left_rows WHERE a>0)", "SELECT b,a FROM (FROM left_rows |> WHERE a>0 |> SELECT a,b)",
      "FROM (FROM left_rows |> WHERE a>0 |> SELECT a,b) |> SELECT b,a",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}
