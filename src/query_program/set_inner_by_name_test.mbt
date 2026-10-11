///|
test "INNER BY NAME aligns evaluated inputs into an authored Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":2}}},{"select":[{"x":"aql_query_expr_0"},{"left_only":"aql_query_expr_1"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":3},"aql_query_expr_1":{"literal":4}}},{"select":[{"x":"aql_query_expr_0"},{"right_only":"aql_query_expr_1"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","select":["x"],"as":"aql_data_set_left_5"},{"from":"aql_data_set_term_3","select":["x"],"as":"aql_data_set_aligned_6"},{"from":"aql_data_set_left_5","append":{"with":"aql_data_set_aligned_6"},"as":"aql_data_0"},{"from":"aql_data_0","select":["x"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("INNER alignment adds no acquisition")
  }
  let actual = compile_data_set(
    "DATA e = SELECT 1 AS x, 2 AS left_only INNER UNION ALL BY NAME SELECT 3 AS x, 4 AS right_only; FROM e |> SELECT x",
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "INNER BY NAME root CTE and Pipe preserve common names and ON spelling" {
  for
    text in [
      "SELECT id, amount AS shared, 10 AS left_only FROM orders INNER UNION ALL BY NAME SELECT amount AS shared, id, 20 AS right_only FROM orders ORDER BY id",
      "SELECT id, amount FROM orders INNER INTERSECT DISTINCT BY NAME SELECT amount, id, 20 AS extra FROM orders",
      "SELECT id, amount FROM orders INNER EXCEPT DISTINCT BY NAME SELECT amount, id, 20 AS extra FROM orders",
      "FROM orders |> SELECT id, amount |> INNER UNION ALL BY NAME ON (`ID`) (FROM orders |> SELECT amount, id) |> ORDER BY ID",
      "WITH chosen AS (SELECT id, amount FROM orders INNER UNION ALL BY NAME SELECT id, 20 AS extra FROM orders) SELECT id FROM chosen ORDER BY id",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(query, values_context(), construction_limits()).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("INNER alignment adds no acquisition")
    }
  }
}

///|
test "SQL INNER chain omits globally absent columns before comparing set types" {
  let sql = "SELECT 1 AS x, 2 AS ignored INNER UNION ALL BY NAME SELECT 3 AS x, 'text' AS ignored INNER UNION ALL BY NAME SELECT 4 AS x"
  let root = compile(
    @query.parse_query(sql, syntax_limits()).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  let data = compile_data_set("DATA e = " + sql + "; FROM e |> SELECT x")
  for actual in [root, data] {
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("SQL INNER chain adds no acquisition")
    }
  }
  // Two sequential Pipe sets compare their intermediate common column.
  let pipe = compile_data_set(
    "DATA e = SELECT 1 AS x, 2 AS ignored |> INNER UNION ALL BY NAME (SELECT 3 AS x, 'text' AS ignored) |> INNER UNION ALL BY NAME (SELECT 4 AS x); FROM e |> SELECT x",
  )
  assert_true(
    @check.check_parsed(pipe, check_environment(), None, check_limits())
    is Rejected(_),
  )
}

///|
test "INNER BY NAME rejects empty common names and missing listed columns" {
  for
    text in [
      "SELECT id FROM orders INNER UNION ALL BY NAME SELECT amount FROM orders",
      "SELECT id, amount FROM orders INNER UNION ALL BY NAME ON (missing) SELECT id, amount FROM orders",
      "SELECT id, amount FROM orders INNER UNION ALL BY NAME ON (amount) SELECT id FROM orders",
      "SELECT id, amount FROM orders INNER UNION ALL BY NAME ON (id, ID) SELECT id, amount FROM orders",
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
