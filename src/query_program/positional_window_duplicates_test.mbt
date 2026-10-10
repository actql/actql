///|
test "terminal positional repeated window aliases preserve opposing order keys" {
  // x=1 yields (1,2), x=2 yields (2,1); reusing the first result would
  // incorrectly make both outputs equal. The left operand names a/b.
  let source = "DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS `N` FROM r ORDER BY a, b"
  let actual = match
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(DuplicateOutput) => fail("positional window aliases: DuplicateOutput")
    Err(UnsupportedAnalytic) =>
      fail("positional window aliases: UnsupportedAnalytic")
    Err(_) => fail("positional window aliases: another refusal")
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
    NeedsInputs(_) => fail("the two window inputs use local Values")
  }
}

///|
test "terminal positional windows retain function identity and empty input" {
  for
    source in [
      "DATA r = SELECT 1 AS x UNION ALL SELECT 1 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, RANK() OVER (ORDER BY x) AS n FROM r ORDER BY a, b",
      "DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT SUM(x) OVER (ORDER BY x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n, COUNT(x) OVER (ORDER BY x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n FROM r ORDER BY a, b",
      "DATA r = SELECT 1 AS x WHERE FALSE; SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r ORDER BY a, b",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
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
      Rejected(issue) =>
        match @check.diagnostic_cause(issue) {
          Source(SourceView(Program(Program(Pipeline(_, cause))))) =>
            fail(source + ": " + @debug.to_string(cause.kind))
          cause => raise cause
        }
      NeedsInputs(_) => fail("the window input uses closed local Values")
    }
  }
  let ordinary = compile(
    @query.parse_query(
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY amount) AS n, ROW_NUMBER() OVER (ORDER BY amount DESC) AS n FROM orders ORDER BY a, b",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(ordinary, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) =>
      match @check.diagnostic_cause(issue) {
        Source(SourceView(Program(Program(Pipeline(_, cause))))) =>
          fail("ordinary window: " + @debug.to_string(cause.kind))
        cause => raise cause
      }
    NeedsInputs(_) => fail("the ordinary window control uses Values")
  }
}

///|
test "positional window slots do not authorize ambiguous or private receivers" {
  let head = "DATA r = SELECT 1 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS `N` FROM r QUALIFY "
  for predicate in ["n > 0", "`N` > 0", "n.member = 1"] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(head + predicate, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=predicate,
    )
  }
  match
    compile_query_script(
      @query.parse_query_script(
        head + "aql_analytic_output_3 > 0",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
    Ok(_) => fail("a private window slot became an authored receiver")
    Err(_) => fail("the private window receiver failed for another reason")
  }
  for
    source in [
      "DATA r = SELECT 1 AS x; SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r",
      "DATA r = SELECT 1 AS x; SELECT 0 AS n UNION ALL BY NAME SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(DuplicateOutput),
      msg=source,
    )
  }
}

///|
test "independent ordinary Program preserves both positional window outputs" {
  // This control is authored without calling frontend lowering. Its expected
  // rows are (0,0), (1,2), (2,1), all nonnullable numeric a/b values.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.window_duplicates","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"asc","nulls":"first"}],"functions":{"up":{"fn":"row_number"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"desc","nulls":"last"}],"functions":{"down":{"fn":"row_number"}}}},{"select":[{"a":"up"},{"b":"down"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the independent window control has no acquisition")
  }
}

///|
test "positional window lowering matches the independent complete DATA Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"x":"aql_query_expr_0"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"x":"aql_query_expr_0"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_term_3"},"as":"aql_data_set_combined_5"},{"from":"aql_data_set_combined_5","select":["x"],"as":"aql_data_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_8"},{"from":"aql_script_seed_8","derive":{"aql_query_expr_0":{"literal":0},"aql_query_expr_1":{"literal":0}}},{"select":[{"a":"aql_query_expr_0"},{"b":"aql_query_expr_1"}],"as":"aql_data_set_term_7"},{"from":"aql_data_0","analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"asc","nulls":"first"}],"functions":{"aql_analytic_output_2":{"fn":"row_number"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"desc","nulls":"last"}],"functions":{"aql_analytic_output_3":{"fn":"row_number"}}}},{"select":[{"aql_set_duplicate_5":"aql_analytic_output_2"},{"aql_set_duplicate_6":"aql_analytic_output_3"}],"as":"aql_data_set_term_9"},{"from":"aql_data_set_term_9","select":[{"a":"aql_set_duplicate_5"},{"b":"aql_set_duplicate_6"}],"as":"aql_data_set_aligned_10"},{"from":"aql_data_set_term_7","append":{"with":"aql_data_set_aligned_10"},"as":"aql_data_set_combined_11"},{"from":"aql_data_set_combined_11","select":["a","b"],"as":"aql_data_6"},{"from":"aql_data_6","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_data_set(
    "DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x; DATA e = SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x) AS n, ROW_NUMBER() OVER (ORDER BY x DESC) AS `N` FROM r; FROM e |> SELECT a, b",
  )
  assert_eq(semantic(actual), semantic(expected))
  for program in [expected, actual] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the complete window correspondence has no acquisition")
    }
  }
}
