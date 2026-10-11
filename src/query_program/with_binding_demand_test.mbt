///|
fn with_demand_program(
  result : Result[@program.Program, Issue],
) -> @program.Program raise {
  match result {
    Ok(program) => program
    Err(BindingPreparation(Demand(WorkLimit))) => fail("Demand WorkLimit")
    Err(BindingPreparation(Demand(ForeignStage))) => fail("Demand ForeignStage")
    Err(BindingPreparation(Demand(InvalidRange))) => fail("Demand InvalidRange")
    Err(BindingPreparation(Demand(MissingImport))) =>
      fail("Demand MissingImport")
    Err(BindingPreparation(SourceProgram(Program(Pipeline(stage, issue))))) =>
      fail("Source pipeline stage \{stage}: " + @debug.to_string(issue.kind))
    Err(BindingPreparation(SourceProgram(BudgetExceeded))) =>
      fail("SourceProgram budget")
    Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) =>
      fail("Local pipeline stage \{stage}: " + @debug.to_string(issue.kind))
    Err(BindingPreparation(LocalProgram(BudgetExceeded))) =>
      fail("LocalProgram budget")
    Err(Construction(issue)) => fail("Construction " + @debug.to_string(issue))
    Err(Admission(issue)) => fail("Admission " + @debug.to_string(issue))
    Err(Expression(issue)) =>
      fail("Expression " + @debug.to_string(issue.issue))
    Err(ExpressionTyping(issue)) =>
      fail("Expression typing " + @debug.to_string(issue.kind))
    Err(UnresolvedRelation(_)) => fail("UnresolvedRelation")
    Err(UnsupportedCte) => fail("UnsupportedCte")
    Err(UnknownColumn) => fail("UnknownColumn")
    Err(
      BindingPreparation(
        SourceProgram(Program(Order(stage, PipelineOrder(issue))))
      )
    ) => fail("Source order stage \{stage}: " + @debug.to_string(issue.kind))
    Err(
      BindingPreparation(
        SourceProgram(Program(Order(stage, ProducerOrder(issue))))
      )
    ) =>
      fail(
        "Source producer order stage \{stage}: " +
        @debug.to_string(issue.issue.kind),
      )
    Err(
      BindingPreparation(
        SourceProgram(Program(Order(stage, ResultOrder(issue))))
      )
    ) =>
      fail(
        "Source result order stage \{stage}: " + @debug.to_string(issue.kind),
      )
    Err(BindingPreparation(SourceProgram(Program(Results(stage, issue))))) =>
      fail("Source Result stage \{stage}: " + @debug.to_string(issue.kind))
    Err(BindingPreparation(SourceRegistration(_))) => fail("SourceRegistration")
    Err(BindingPreparation(SourceProgram(_))) =>
      fail("Other SourceProgram refusal")
    Err(BindingPreparation(_)) => fail("Other BindingPreparation refusal")
    Err(_) => fail("Other lowerer refusal")
  }
}

///|
test "valid unused WITH Source emits the independent source-free Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for captured in [false, true] {
    let actual = with_demand_program(
      compile_query_script(
        @query.parse_query_script(
          "WITH unused AS (SELECT id FROM objects) SELECT 1 AS id",
          syntax_limits(),
        ).unwrap(),
        source_member_context(captured~),
        construction_limits(),
      ),
    )
    assert_eq(semantic(actual), semantic(expected))
    assert_eq(@program.stage_count(actual), 1)
    // An actual provider call and its zero-I/O public receipt remain separate
    // acceptance. This complete machine Program has no acquisition declaration.
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail("unused Source must not be requested by the emitted Program")
    }
  }
}

///|
test "nested unused WITH Source is independent of the demanded outer body" {
  let result = compile_query_script(
    @query.parse_query_script(
      "WITH kept AS (WITH unused AS (SELECT id FROM objects) SELECT 1 AS id) SELECT id FROM kept",
      syntax_limits(),
    ).unwrap(),
    source_member_context(captured=true),
    construction_limits(),
  )
  let actual = with_demand_program(result)
  let body = semantic(actual)
  assert_eq(@program.stage_count(actual), 1)
  assert_false(body.contains("\"connector\""))
  assert_false(body.contains("\"result\":{\"result\":\"source\""))
  assert_true(body.contains("\"literal\":1"))
}

///|
test "demanded WITH body keeps assertions and non-output evaluations" {
  let actual = compile_with_set(
    "WITH kept AS (SELECT 1 AS id, 9 AS ignored |> ASSERT UNIQUE BY (id) |> SELECT id) FROM kept |> SELECT id",
  )
  let body = semantic(actual)
  assert_true(body.contains("\"assert_rows\":{\"unique_by\":[\"id\"]}"))
  assert_true(body.contains("\"literal\":9"))
  assert_true(body.contains("\"fields\":[\"id\"]"))
}

///|
test "unused Graph value validation is absent from final executable steps" {
  let actual = compile_with_set(
    "WITH n AS (SELECT 1 AS id UNION ALL SELECT 1 AS id), unused AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES))) SELECT 1 AS answer",
  )
  let body = semantic(actual)
  assert_false(body.contains("\"graph\""))
  assert_false(body.contains("\"append\""))
  assert_eq(@program.stage_count(actual), 1)
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("unused Graph must not retain a dynamic construction obligation")
  }
}
