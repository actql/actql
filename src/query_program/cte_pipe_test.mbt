///|
test "SELECT and Pipe CTE forms match an independently authored Program" {
  // Authored from Stage Result and projection contracts, not compiler output.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.sql_set","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"a":{"type":"number","nullable":true},"b":{"type":"string","nullable":false}},"rows":[{"a":1,"b":"x"},{"a":1,"b":"x"},{"a":2,"b":"y"},{"a":null,"b":"n"}]},"as":"left_rows"},{"from":"left_rows","filter":{"gt":[{"field":"a"},{"literal":0}]}},{"select":["a","b"],"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["a","b"]}}},{"id":"main","inputs":{"chosen":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"chosen","select":["b","a"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["b","a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "WITH chosen AS (SELECT a, b FROM left_rows WHERE a > 0) SELECT b, a FROM chosen",
      "WITH chosen AS (SELECT a, b FROM left_rows WHERE a > 0) FROM chosen |> SELECT b, a",
      "WITH chosen AS (FROM left_rows |> WHERE a > 0 |> SELECT a, b) SELECT b, a FROM chosen",
      "WITH chosen AS (FROM left_rows |> WHERE a > 0 |> SELECT a, b) FROM chosen |> SELECT b, a",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, set_context(), construction_limits()).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("Values CTE should have closed inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "Pipe CTE chains retain prior scope and reject unchecked declarations" {
  let chain = @query.parse_query(
    "WITH first AS (FROM left_rows |> SELECT a, b), second AS (FROM first AS old |> AS current |> SELECT current.a AS a, current.b AS b) FROM second |> SELECT b, a",
    syntax_limits(),
  ).unwrap()
  let program = compile(chain, set_context(), construction_limits()).unwrap()
  assert_eq(@program.stage_count(program), 3)
  assert_eq(semantic(program).split("\"values\":").length(), 2)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    _ => fail("Pipe CTE chain must reach the ordinary checker")
  }
  for
    text in [
      "WITH c AS (FROM left_rows AS old |> AS current |> SELECT old.a) FROM c |> SELECT a",
      "WITH c AS (FROM later |> SELECT a), later AS (FROM left_rows |> SELECT a) FROM c |> SELECT a",
      "WITH c AS (FROM c |> SELECT a) FROM c |> SELECT a", "WITH c AS (FROM left_rows |> SELECT a) FROM c |> SELECT b",
      "WITH c AS (FROM left_rows |> SELECT a), C AS (FROM left_rows |> SELECT a) FROM c |> SELECT a",
    ] {
    match @query.parse_query(text, syntax_limits()) {
      Err(_) => ()
      Ok(query) =>
        assert_true(
          compile(query, set_context(), construction_limits()) is Err(_),
          msg=text,
        )
    }
  }
}

///|
test "captured WHERE-only and source-only CTEs bind the retained producer" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"capture","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","filter":{"gt":[{"field":"amount"},{"literal":10}]}},{"select":["id","customer_id","status","amount"],"as":"aql_capture_0"}],"results":{"source":{"from":"aql_capture_0","fields":["id","customer_id","status","amount"]}}},{"id":"main","inputs":{"chosen":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"chosen","select":["id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    text in [
      "WITH chosen AS (FROM orders |> WHERE amount > 10) FROM chosen |> SELECT id",
      "WITH first AS (FROM orders |> WHERE amount > 10), chosen AS (FROM first) FROM chosen |> SELECT id",
      "WITH chosen AS (FROM orders |> WHERE amount > 10) SELECT id FROM chosen",
      "WITH chosen AS (FROM orders |> WHERE amount > 10 |> AS fresh) FROM chosen |> SELECT id",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, context, construction_limits()).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail("captured CTE must use the ordinary checker")
    }
  }
  let query = @query.parse_query(
    "WITH chosen AS (FROM orders) FROM chosen |> SELECT id",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, context, construction_limits()).unwrap()
  assert_eq(@program.stage_count(program), 2)
  assert_true(!semantic(program).contains("aql_cte_0"))
}
