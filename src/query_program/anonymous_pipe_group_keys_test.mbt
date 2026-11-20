///|
test "unnamed Pipe grouping keys use final visible positions and reserve real names" {
  for
    (source, fields) in [
      ("FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1", ["f0_", "n"]),
      ("FROM pair |> AGGREGATE GROUP BY x + 1", ["f0_"]),
      ("FROM pair |> AGGREGATE COUNT(*) AS f0_ GROUP BY x + 1", ["f0__", "f0_"]),
      (
        "FROM pair |> AGGREGATE COUNT(*) AS f1_ GROUP BY x, x + 1, y + 1 AS `Quoted`",
        ["x", "f1__", "Quoted", "f1_"],
      ),
      ("FROM pair |> AGGREGATE COUNT(*) AS x GROUP BY (x)", ["f0_", "x"]),
      (
        "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1, x + 1",
        ["f0_", "f1_", "n"],
      ),
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let program = compile(query, pair_context(), construction_limits()).unwrap()
    assert_eq(anonymous_result_fields(program), fields, msg=source)
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the existing scalar grouping fixture remains closed")
    }
  }
}

///|
test "unnamed Pipe grouping output never supplies a later SQL name" {
  for
    tail in [
      "AGGREGATE COUNT(*) AS m GROUP BY aql_group_output_4", "AGGREGATE COUNT(aql_group_output_4) AS m",
      "ASSERT UNIQUE BY (aql_group_output_4)", "DROP aql_group_output_4", "RENAME aql_group_output_4 AS exposed",
      "SELECT f0_", "SELECT aql_group_key_0", "SELECT aql_group_output_4", "ORDER BY f0_",
      "ORDER BY aql_group_key_0", "ORDER BY aql_group_output_4", "WHERE f0_ > 0",
      "AS row |> SELECT row.f0_", "AS row |> SELECT (row).f0_",
    ] {
    let source = "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> " +
      tail
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Err(UnknownColumn) => ()
      Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(_) => fail("wrong unnamed grouping refusal: " + source)
      Ok(_) =>
        fail("a private grouping value became an authored name: " + source)
    }
  }
  for
    source in [
      "WITH t AS (SELECT 1 AS x), grouped AS (FROM t |> AGGREGATE COUNT(*) AS n GROUP BY x + 1) SELECT f0_ FROM grouped",
      "WITH t AS (SELECT 1 AS x), grouped AS (FROM t |> AGGREGATE COUNT(*) AS n GROUP BY x + 1) SELECT grouped.f0_ FROM grouped",
      "WITH t AS (SELECT 1 AS x), grouped AS (FROM t |> AGGREGATE COUNT(*) AS n GROUP BY x + 1) SELECT * FROM grouped UNION ALL BY NAME SELECT 2 AS f0_, 1 AS n",
    ] {
    match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn) | Err(UnsupportedProjection) => ()
      Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(_) => fail("wrong retained unnamed grouping refusal: " + source)
      Ok(_) =>
        fail("a retained anonymous grouping output became named: " + source)
    }
  }
}

///|
test "Pipe grouping preserves genuine implicit explicit and authored display-spelled names" {
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x, y + 1 |> SELECT x, n", "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS f0_, y + 1 |> SELECT f0_, n |> ORDER BY f0_",
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS `Quoted`, y + 1 |> SELECT `Quoted`, n",
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1, y + 1 AS aql_group_output_0 |> SELECT aql_group_output_0, n",
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY pair.x, y + 1 |> SELECT x, n",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
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
      NeedsInputs(_) => fail("named grouping controls remain closed")
    }
  }
  let retained = anonymous_result_program(
    "WITH t AS (SELECT 1 AS x), grouped AS (FROM t |> AGGREGATE COUNT(*) AS n GROUP BY x + 1) SELECT * FROM grouped",
  )
  assert_eq(anonymous_result_fields(retained), ["f0_", "n"])
}

///|
test "unnamed Pipe grouping shorthand sorts its evaluated physical key once" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"aql_group_output_4":"aql_group_key_0"},"n"]},{"sort":[{"field":"aql_group_output_4","dir":"desc","nulls":"last"}]},{"select":["aql_group_output_4","n"]},{"select":[{"f0_":"aql_group_output_4"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["f0_","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) =>
      fail("the independent evaluated grouping Program is closed")
  }
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY x + 1 DESC NULLS LAST",
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 DESC NULLS LAST",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(
      semantic(program),
      semantic(expected),
      msg=source + " actual=" + semantic(program),
    )
  }
}
