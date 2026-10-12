///|
test "BY NAME ON reorders both inputs into the authored Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":2}}},{"select":[{"x":"aql_query_expr_0"},{"y":"aql_query_expr_1"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":3},"aql_query_expr_1":{"literal":4}}},{"select":[{"y":"aql_query_expr_0"},{"x":"aql_query_expr_1"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","select":["y","x"],"as":"aql_data_set_left_5"},{"from":"aql_data_set_left_5","append":{"with":"aql_data_set_term_3"},"as":"aql_script_cte_0"},{"from":"aql_script_cte_0","select":["y","x"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["y","x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  // The common Program and its expected column order precede parser support.
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("BY NAME ON adds no acquisition")
  }
  let actual = compile_with_set(
    "WITH e AS (SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (y, x) SELECT 3 AS y, 4 AS x) FROM e |> SELECT y, x",
  )
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("BY NAME ON adds no acquisition")
  }
}

///|
test "BY NAME ON SQL and Pipe sets retain explicit output spelling" {
  for
    text in [
      "SELECT id, amount FROM orders UNION ALL BY NAME ON (AMOUNT, `ID`) SELECT amount, id FROM orders ORDER BY AMOUNT, ID",
      "SELECT id, amount FROM orders UNION DISTINCT BY NAME ON (amount, id) SELECT amount, id FROM orders",
      "SELECT id, amount FROM orders INTERSECT DISTINCT BY NAME ON (amount, id) SELECT amount, id FROM orders",
      "SELECT id, amount FROM orders EXCEPT DISTINCT BY NAME ON (amount, id) SELECT amount, id FROM orders",
      "FROM orders |> SELECT id, amount |> UNION ALL BY NAME ON (amount, id) (FROM orders |> SELECT amount, id) |> ORDER BY amount, id",
      "FROM orders |> SELECT id, amount |> UNION ALL BY NAME ON (amount, id) (FROM orders |> SELECT amount, id) |> UNION ALL BY NAME ON (id, amount) (FROM orders |> SELECT amount, id) |> ORDER BY id, amount",
      "WITH chosen AS (SELECT id, amount FROM orders UNION ALL BY NAME ON (amount, id) SELECT amount, id FROM orders) SELECT amount, id FROM chosen ORDER BY amount, id",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = match compile(query, values_context(), construction_limits()) {
      Ok(program) => program
      Err(_) => fail(text)
    }
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("BY NAME ON adds no acquisition")
    }
    let expected_fields = if text.contains("(AMOUNT, `ID`)") {
      "\"fields\":[\"AMOUNT\",\"ID\"]"
    } else if text.contains("ORDER BY id, amount") {
      "\"fields\":[\"id\",\"amount\"]"
    } else {
      "\"fields\":[\"amount\",\"id\"]"
    }
    assert_true(semantic(actual).contains(expected_fields), msg=text)
  }
}

///|
test "BY NAME ON rejects invalid lists with the set diagnostic" {
  for
    text in [
      "SELECT id, amount FROM orders UNION ALL BY NAME ON (id) SELECT id, amount FROM orders",
      "SELECT id FROM orders UNION ALL BY NAME ON (id, amount) SELECT id, amount FROM orders",
      "SELECT id, amount FROM orders UNION ALL BY NAME ON (id, amount) SELECT id FROM orders",
      "SELECT id, amount FROM orders UNION ALL BY NAME ON (id, ID) SELECT id, amount FROM orders",
      "SELECT id, amount FROM orders UNION ALL BY NAME ON (id, `ID`) SELECT id, amount FROM orders",
      "SELECT id, amount FROM orders UNION ALL BY NAME ON (id, missing) SELECT id, amount FROM orders",
      "FROM orders |> SELECT id, amount |> UNION ALL BY NAME ON (id) (FROM orders |> SELECT id, amount)",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedSet),
      msg=text,
    )
  }
}

///|
test "BY NAME ON WITH has the same set diagnostic and common type checking" {
  for
    text in [
      "WITH e AS (SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (x) SELECT 3 AS x, 4 AS y) FROM e |> SELECT x",
      "WITH e AS (SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (`x`, X) SELECT 3 AS x, 4 AS y) FROM e |> SELECT x",
      "WITH e AS (SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (y, x) SELECT 3 AS y) FROM e |> SELECT y, x",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedSet),
      msg=text,
    )
  }
  expect_with_set_append_refusal(
    "WITH e AS (SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (y, x) SELECT 'wrong' AS y, 4 AS x) FROM e |> SELECT y, x",
    "y",
  )
}

///|
fn expect_with_set_append_refusal(text : String, field : String) -> Unit raise {
  let result = compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  )
  guard result is Err(BindingPreparation(LocalProgram(Pipeline(_, issue)))) else {
    fail("expected the common static WITH Append refusal")
  }
  assert_eq(
    issue.kind,
    @pipeline.Append(IncompatibleContracts(@schema.Unqualified(field), [])),
  )
}
