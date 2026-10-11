///|
fn independent_from_unpivot_program() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.from_unpivot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"input"},{"from":"input","unpivot":{"columns":["x","y"],"keep":[],"value_column":"value","name_column":"label"}},{"sort":[{"field":"label","dir":"asc","nulls":"first"},{"field":"value","dir":"asc","nulls":"first"}]},{"select":["value","label"],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["value","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "FROM UNPIVOT has an independent ordinary Program control" {
  match
    @check.check_parsed(
      independent_from_unpivot_program(),
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("independent UNPIVOT Values input must be closed")
  }
}

///|
test "SQL FROM UNPIVOT reaches the existing checked operation" {
  let source = "SELECT value,label FROM t UNPIVOT INCLUDE NULLS(value FOR label IN(x,y)) ORDER BY label,value"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) =>
      fail("FROM UNPIVOT syntax refusal: " + reason)
    Err(_) => fail("unexpected FROM UNPIVOT parse refusal")
  }
  let actual = compile(query, join_order_context(), construction_limits()).unwrap()
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed SQL FROM UNPIVOT control")
  }
}

///|
test "FROM UNPIVOT matches independent producer and consumer stages" {
  // The producer executes one ordinary UNPIVOT, projects public names, and
  // the consumer orders those retained values. No input range survives.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","unpivot":{"columns":["x","y"],"keep":[],"name_column":"aql_unpivot_name_2","value_column":"aql_unpivot_value_3"}},{"select":[{"value":"aql_unpivot_value_3"},{"label":"aql_unpivot_name_2"}],"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["value","label"]}}},{"id":"main","inputs":{"aql_query_source_0":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"aql_query_source_0","select":["value","label"]},{"sort":[{"field":"label","dir":"asc","nulls":"first"},{"field":"value","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT value,label FROM t UNPIVOT INCLUDE NULLS(value FOR label IN(x,y)) ORDER BY label,value",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "FROM UNPIVOT preserves aliases derived tables CTEs and both JOIN ports" {
  for
    source in [
      "FROM t UNPIVOT(value FOR label IN(x,y)) shaped |> WHERE shaped.value > 1 |> SELECT shaped.label,shaped.value |> ORDER BY label,value |> LIMIT 2",
      "SELECT shaped.value,shaped.label FROM t original UNPIVOT(value FOR label IN(x,y)) AS shaped WHERE shaped.value > 1 ORDER BY label,value LIMIT 2",
      "SELECT `U`.value,`U`.label FROM (SELECT 1 AS x,2 AS y) UNPIVOT(value FOR label IN(`x`,y)) `U` ORDER BY label",
      "WITH wide AS (SELECT 1 AS x,2 AS y) SELECT value,label FROM wide UNPIVOT(value FOR label IN(x,y)) ORDER BY label",
      "SELECT shaped.value,r.k FROM t UNPIVOT(value FOR label IN(x,y)) shaped JOIN r ON shaped.value=r.k MAX_OUTPUT_ROWS 10 ORDER BY value,k",
      "SELECT shaped.value,r.k FROM r JOIN t UNPIVOT(value FOR label IN(x,y)) shaped ON r.k=shaped.value MAX_OUTPUT_ROWS 10 ORDER BY value,k",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let actual = match
      compile(query, join_order_context(), construction_limits()) {
      Ok(program) => program
      Err(UnsupportedCte) => fail("UnsupportedCte: " + source)
      Err(UnsupportedProjection) => fail("UnsupportedProjection: " + source)
      Err(UnsupportedJoin) => fail("UnsupportedJoin: " + source)
      Err(Expression(issue)) =>
        fail(@debug.to_string(issue.issue) + ": " + source)
      Err(UnknownColumn) => fail("UnknownColumn: " + source)
      Err(UnknownRelation) => fail("UnknownRelation: " + source)
      Err(_) => fail("another lowering refusal: " + source)
    }
    if source.contains("MAX_OUTPUT_ROWS 10") {
      assert_true(semantic(actual).contains("\"max_output_rows\":10"))
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
      NeedsInputs(_) => fail("closed FROM UNPIVOT shape: " + source)
    }
  }
}

///|
test "FROM UNPIVOT keeps NULL inclusion and empty typed input" {
  for
    source in [
      "SELECT value,label FROM (SELECT element AS x,element AS y FROM UNNEST([NULL,1,1]) element) UNPIVOT INCLUDE NULLS(value FOR label IN(x,y)) ORDER BY label,value",
      "SELECT value,label FROM (SELECT element AS x,element AS y FROM UNNEST([NULL,1,1]) element) UNPIVOT EXCLUDE NULLS(value FOR label IN(x,y)) ORDER BY label,value",
      "SELECT value,label FROM (SELECT x,y FROM t WHERE FALSE) UNPIVOT INCLUDE NULLS(value FOR label IN(x,y)) ORDER BY label,value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
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
      NeedsInputs(_) => fail("closed NULL/empty UNPIVOT shape")
    }
    if source.contains("EXCLUDE NULLS") {
      assert_true(semantic(actual).contains("\"is_null\""))
    }
  }
}

///|
test "FROM UNPIVOT does not restore consumed columns or its old input range" {
  for
    source in [
      "SELECT old.x FROM t old UNPIVOT(value FOR label IN(x,y)) shaped", "SELECT x FROM t UNPIVOT(value FOR label IN(x,y))",
      "SELECT shaped.x FROM t UNPIVOT(value FOR label IN(x,y)) shaped",
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
}

///|
test "FROM UNPIVOT preserves typed value-table and destination refusals" {
  for
    source in [
      "SELECT value,label FROM (FROM UNNEST([1,2]) element) UNPIVOT(value FOR label IN(element))",
      "WITH a AS (FROM UNNEST([1,2]) element) SELECT value,label FROM a UNPIVOT(value FOR label IN(a))",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=source,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM t UNPIVOT(value FOR VALUE IN(x,y))",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}
