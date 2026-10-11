///|
test "CORRESPONDING aligns evaluated inputs into an authored Program" {
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
    NeedsInputs(_) => fail("CORRESPONDING alignment adds no acquisition")
  }
  let actual = compile_data_set(
    "DATA e = SELECT 1 AS x, 2 AS left_only UNION ALL CORRESPONDING SELECT 3 AS x, 4 AS right_only; FROM e |> SELECT x",
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "STRICT CORRESPONDING BY reorders both inputs into the authored Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":2}}},{"select":[{"x":"aql_query_expr_0"},{"y":"aql_query_expr_1"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":3},"aql_query_expr_1":{"literal":4}}},{"select":[{"y":"aql_query_expr_0"},{"x":"aql_query_expr_1"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","select":["y","x"],"as":"aql_data_set_left_5"},{"from":"aql_data_set_left_5","append":{"with":"aql_data_set_term_3"},"as":"aql_data_0"},{"from":"aql_data_0","select":["y","x"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["y","x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  // The common Program and its expected column order precede parser support.
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("STRICT CORRESPONDING BY adds no acquisition")
  }
  let actual = compile_data_set(
    "DATA e = SELECT 1 AS x, 2 AS y UNION ALL STRICT CORRESPONDING BY (y, x) SELECT 3 AS y, 4 AS x; FROM e |> SELECT y, x",
  )
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("STRICT CORRESPONDING BY adds no acquisition")
  }
}

///|
test "CORRESPONDING root CTE and Pipe preserve common names and BY spelling" {
  for
    text in [
      "SELECT id, amount AS shared, 10 AS left_only FROM orders UNION ALL CORRESPONDING SELECT amount AS shared, id, 20 AS right_only FROM orders ORDER BY id",
      "SELECT id, amount FROM orders INTERSECT DISTINCT CORRESPONDING SELECT amount, id, 20 AS extra FROM orders",
      "SELECT id, amount FROM orders EXCEPT DISTINCT CORRESPONDING SELECT amount, id, 20 AS extra FROM orders",
      "FROM orders |> SELECT id, amount |> UNION ALL CORRESPONDING BY (`ID`) (FROM orders |> SELECT amount, id) |> ORDER BY ID",
      "WITH chosen AS (SELECT id, amount FROM orders UNION ALL CORRESPONDING SELECT id, 20 AS extra FROM orders) SELECT id FROM chosen ORDER BY id",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(query, values_context(), construction_limits()).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("CORRESPONDING alignment adds no acquisition")
    }
  }
}

///|
test "SQL CORRESPONDING chain omits globally absent columns before comparing set types" {
  let sql = "SELECT 1 AS x, 2 AS ignored UNION ALL CORRESPONDING SELECT 3 AS x, 'text' AS ignored UNION ALL CORRESPONDING SELECT 4 AS x"
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
      NeedsInputs(_) => fail("SQL CORRESPONDING chain adds no acquisition")
    }
  }
  // Two sequential Pipe sets compare their intermediate common column.
  let pipe = compile_data_set(
    "DATA e = SELECT 1 AS x, 2 AS ignored |> UNION ALL CORRESPONDING (SELECT 3 AS x, 'text' AS ignored) |> UNION ALL CORRESPONDING (SELECT 4 AS x); FROM e |> SELECT x",
  )
  assert_true(
    @check.check_parsed(pipe, check_environment(), None, check_limits())
    is Rejected(_),
  )
}

///|
test "CORRESPONDING rejects empty common names and missing listed columns" {
  for
    text in [
      "SELECT id FROM orders UNION ALL CORRESPONDING SELECT amount FROM orders",
      "SELECT id, amount FROM orders UNION ALL CORRESPONDING BY (missing) SELECT id, amount FROM orders",
      "SELECT id, amount FROM orders UNION ALL CORRESPONDING BY (amount) SELECT id FROM orders",
      "SELECT id, amount FROM orders UNION ALL CORRESPONDING BY (id, ID) SELECT id, amount FROM orders",
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
