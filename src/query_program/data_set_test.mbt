///|
fn compile_data_set(text : String) -> @program.Program raise {
  let script = match @query.parse_query_script(text, syntax_limits()) {
    Ok(script) => script
    Err(_) => fail("syntax: " + text)
  }
  match
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(_) => fail("lowering: " + text)
  }
}

///|
test "DATA UNION ALL has the independently authored one-stage Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":10}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":11}}},{"select":[{"other":"aql_query_expr_0"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_3","select":[{"id":"other"}],"as":"aql_data_set_aligned_5"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_aligned_5"},"as":"aql_data_set_combined_6"},{"from":"aql_data_set_combined_6","select":["id"],"as":"aql_data_0"},{"from":"aql_data_0","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_data_set(
    "DATA e = SELECT 10 AS id UNION ALL SELECT 11 AS other; FROM e |> SELECT id",
  )
  assert_eq(semantic(actual), semantic(expected))
  assert_eq(@program.stage_count(actual), 1)
  assert_eq(@program.export_count(actual), 1)
  for program in [expected, actual] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("DATA set adds no acquisition")
    }
  }
}

///|
test "DATA set uses shared alignment duplicate and bounded ordering owners" {
  for
    text in [
      "DATA e = SELECT 1 AS x, 2 AS y UNION ALL BY NAME SELECT 3 AS y, 4 AS x; FROM e |> SELECT x, y",
      "DATA e = SELECT 1 AS x UNION DISTINCT SELECT 1 AS y; FROM e |> SELECT x",
      "DATA e = SELECT 1 AS x INTERSECT DISTINCT SELECT 1 AS y; FROM e |> SELECT x",
      "DATA e = SELECT 1 AS x EXCEPT DISTINCT SELECT 2 AS y; FROM e |> SELECT x",
      "DATA e = SELECT 2 AS x UNION ALL SELECT 1 AS y ORDER BY x + 1, x + 1 DESC LIMIT 1; FROM e |> SELECT x",
      "DATA n = SELECT 1 AS x; DATA e = FROM n |> SELECT x |> UNION ALL (FROM n |> SELECT x); FROM e |> SELECT x",
    ] {
    let program = compile_data_set(text)
    assert_eq(@program.stage_count(program), 1)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail(text)
    }
  }
  let ordered = semantic(
    compile_data_set(
      "DATA e = SELECT 2 AS x UNION ALL SELECT 1 AS y ORDER BY x + 1, x + 1 DESC LIMIT 1; FROM e |> SELECT x",
    ),
  )
  // One hidden expression slot is reused by both terms, then projected away.
  assert_eq(ordered.split("\"aql_set_sort_1\":").length(), 2)
  assert_true(
    ordered.contains(
      "\"sort\":[{\"dir\":\"asc\",\"field\":\"aql_set_sort_1\",\"nulls\":\"first\"},{\"dir\":\"desc\",\"field\":\"aql_set_sort_1\",\"nulls\":\"last\"}]",
    ),
  )
  assert_true(ordered.contains("\"fields\":[\"x\"]"))
}

///|
test "DATA sets reject shape scope nested publication and incompatible types" {
  for
    text in [
      "DATA e = SELECT 1 AS x UNION ALL SELECT 2 AS y, 3 AS z; FROM e |> SELECT x",
      "DATA e = SELECT 1 AS x UNION ALL BY NAME SELECT 2 AS y; FROM e |> SELECT x",
      "DATA e = SELECT 1 AS x UNION ALL SELECT 2 AS y ORDER BY y + 1; FROM e |> SELECT x",
      "DATA e = SELECT 1 AS x UNION ALL (SELECT 2 AS x |> RESULT hidden); FROM e |> SELECT x",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
  let bad_type = compile_data_set(
    "DATA e = SELECT 1 AS x UNION ALL SELECT 'wrong' AS x; FROM e |> SELECT x",
  )
  assert_true(
    @check.check_parsed(bad_type, check_environment(), None, check_limits())
    is Rejected(_),
  )
  let query = @query.parse_query_script(
    "DATA e = SELECT 2 AS x UNION ALL SELECT 1 AS x ORDER BY x + 1; FROM e |> SELECT x",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(query, { ..fixture_context(), inputs: [], }, {
      ..construction_limits(),
      max_expression_work: 1,
    })
    is Err(Expression(_)),
  )
}
