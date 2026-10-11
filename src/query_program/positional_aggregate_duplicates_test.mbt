///|
test "terminal positional repeated aggregate aliases preserve each call's input" {
  // Source-free COUNT(*) is one; COUNT(typed NULL) is zero. A repeated alias
  // cannot select the first call twice or reject values matched by position.
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS `N` ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n WHERE FALSE ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n HAVING COUNT(*) > 0 ORDER BY a, b",
      "DATA r = SELECT 1 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n FROM r AS n GROUP BY n.x HAVING n.x > 0 ORDER BY a, b",
    ] {
    let program = match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedAggregate) =>
        fail("repeated aggregate name: UnsupportedAggregate")
      Err(DuplicateOutput) => fail("repeated aggregate name: DuplicateOutput")
      Err(_) => fail("repeated aggregate name: another rejection")
    }
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("source-free aggregates have no acquisition")
    }
  }
}

///|
test "repeated aggregate aliases cannot supply an ambiguous HAVING receiver" {
  for suffix in ["HAVING n > 0", "HAVING `N` > 0", "HAVING n.member = 1"] {
    let source = "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS `N` " +
      suffix
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=source,
    )
  }
}

///|
test "repeated aggregate aliases cannot supply an ambiguous QUALIFY receiver" {
  let head = "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n, ROW_NUMBER() OVER (ORDER BY t.x) AS rn FROM t GROUP BY t.x QUALIFY "
  let control = match
    compile(
      @query.parse_query(head + "t.x > 0 AND rn = 1", syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedAggregate) => fail("QUALIFY control: UnsupportedAggregate")
    Err(UnsupportedProjection) => fail("QUALIFY control: UnsupportedProjection")
    Err(AmbiguousColumn) => fail("QUALIFY control: AmbiguousColumn")
    Err(UnknownColumn) => fail("QUALIFY control: UnknownColumn")
    Err(UnsupportedAnalytic) => fail("QUALIFY control: UnsupportedAnalytic")
    Err(UnsupportedSet) => fail("QUALIFY control: UnsupportedSet")
    Err(DuplicateOutput) => fail("QUALIFY control: DuplicateOutput")
    Err(Expression({ issue: @expression.UnknownReference, .. })) =>
      fail("QUALIFY control: UnknownReference")
    Err(Expression(_)) => fail("QUALIFY control: Expression")
    Err(ExpressionTyping(_)) => fail("QUALIFY control: ExpressionTyping")
    Err(_) => fail("QUALIFY control: another rejection")
  }
  match
    @check.check_parsed(control, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the QUALIFY control uses local Values")
  }
  for predicate in ["n > 0", "`N` > 0", "n.member = 1"] {
    assert_true(
      compile(
        @query.parse_query(head + predicate, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=predicate,
    )
  }
}

///|
test "repeated aggregate physical slots cannot become authored HAVING names" {
  for reference in ["aql_select_aggregate_2", "`AQL_SELECT_AGGREGATE_3`"] {
    let source = "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n HAVING " +
      reference +
      " > 0"
    match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Ok(_) => fail("an aggregate's internal slot became an authored name")
      Err(_) => fail("the private reference failed for another reason")
    }
  }
}

///|
test "an independent ordinary Program distinguishes the two COUNT inputs" {
  // One input row has a nullable numeric NULL. COUNT(*) counts that row,
  // while COUNT(field) excludes its NULL. This control does not call lowering.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.aggregate_duplicates","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"nullable_input":{"type":"number","nullable":true}},"rows":[{"nullable_input":null}]},"as":"input"},{"from":"input","group":{"by":[],"aggregates":{"one":{"fn":"count"},"zero":{"fn":"count","field":"nullable_input"}}}},{"select":[{"a":"one"},{"b":"zero"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n ORDER BY a, b",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  for program in [expected, actual] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) =>
        match @check.diagnostic_cause(issue) {
          Source(SourceView(Program(Program(Pipeline(_, cause))))) =>
            fail("independent COUNT pipeline: " + @debug.to_string(cause.kind))
          Source(cause) => raise cause
          cause => raise cause
        }
      NeedsInputs(_) => fail("the independent control has no external inputs")
    }
  }
}

///|
test "duplicate aggregate lowering matches an independently authored complete Program" {
  // Only the two authored aliases reserve aggregate slots two/three; the
  // source-free unit is not a visible input field.
  // The terminal projection reserves those two slots plus both aliases, so
  // its positional fields are four/five. No COUNT argument is rewritten.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":0},"aql_query_expr_1":{"literal":0}}},{"select":[{"a":"aql_query_expr_0"},{"b":"aql_query_expr_1"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","group":{"by":[],"aggregates":{"aql_select_aggregate_2":{"fn":"count"},"aql_select_aggregate_3":{"fn":"count","expr":{"cast":{"value":{"literal":null},"target":{"type":"number"}}}}}}},{"select":[{"a":"aql_select_aggregate_2"},{"b":"aql_select_aggregate_3"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_term_3"},"as":"aql_data_0"},{"from":"aql_data_0","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_data_set(
    "DATA e = SELECT 0 AS a, 0 AS b UNION ALL SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n; FROM e |> SELECT a, b",
  )
  assert_eq(semantic(actual), semantic(expected))
  for program in [expected, actual] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("the COUNT correspondence has no external inputs")
    }
  }
}
