///|
fn data_acquisition_environment() -> @check.CheckEnvironment {
  @check.checking_environment(
    @check.checking_environment_wire(check_environment()),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    graph=true,
  )
}

///|
test "DATA imports the existing input once without adding a DATA capture" {
  let text = "DATA kept = FROM orders |> SELECT id; FROM kept |> SELECT id"
  let actual = compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  // This is authored from the existing input/step contract. DATA creates a
  // logical producer in main, not another acquisition or exported Result.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","select":["id"],"as":"aql_data_1"},{"from":"aql_data_1","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_eq(@program.stage_count(actual), 1)
  for program in [actual, expected] {
    match
      @check.check_parsed(
        program,
        data_acquisition_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("schema input is already declared")
    }
  }
}

///|
test "DATA preserves the requested capture Result and complete schema" {
  let text = "DATA kept = FROM orders |> SELECT id; FROM kept |> SELECT id"
  let actual = compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    { ..fixture_context(), captured_stage: Some("capture"), },
    construction_limits(),
  ).unwrap()
  // DATA does not move its projection or predicate into the acquisition.
  // That same complete captured Result can serve another DATA consumer.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"capture","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","filter":{"literal":true}},{"select":["id","customer_id","status","amount"],"as":"aql_capture_0"}],"results":{"source":{"from":"aql_capture_0","fields":["id","customer_id","status","amount"]}}},{"id":"main","inputs":{"orders":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"orders","select":["id"],"as":"aql_data_1"},{"from":"aql_data_1","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_eq(@program.stage_count(actual), 2)
  assert_eq(@program.export_count(actual), 1)
  for program in [actual, expected] {
    match
      @check.check_parsed(
        program,
        data_acquisition_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("capture uses the admitted schema input")
    }
  }
}

///|
test "DATA set and constructor references reuse one captured input" {
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    (text, needs_source_view) in [
      (
        "DATA kept = FROM orders |> WHERE amount > 10 |> SELECT id; DATA combined = FROM kept |> SELECT id |> UNION ALL (FROM orders |> SELECT id); FROM combined |> SELECT id",
        false,
      ),
      (
        "DATA g = PROPERTY GRAPH (NODE TABLES (orders AS Person KEY (id) LABEL Person PROPERTIES (id), orders AS Company KEY (id) LABEL Company PROPERTIES (id))); FROM GRAPH g |> MATCH (a:Person) |> SELECT a.id",
        true,
      ),
    ] {
    let program = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    let body = semantic(program)
    assert_eq(@program.stage_count(program), 2)
    assert_eq(@program.export_count(program), 1)
    assert_eq(body.split("\"carrier\":\"relation\"").length(), 2)
    assert_eq(body.split("\"stage\":\"capture\"").length(), 2)
    assert_true(body.contains("\"filter\":{\"literal\":true}"))
    match
      @check.check_parsed(
        program,
        data_acquisition_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => assert_false(needs_source_view)
      Rejected(diagnostic) =>
        match @check.diagnostic_cause(diagnostic) {
          Source(SourceView(Program(Program(Pipeline(_, issue))))) => {
            // The bare schema fixture is not an admitted Source View. Retain
            // the common owner's refusal; DATA cannot grant Graph provenance.
            assert_true(needs_source_view)
            assert_eq(issue.kind, MissingPropertyProducerDefinition)
          }
          other => raise other
        }
      NeedsInputs(_) => fail("all declared sources remain in the Program")
    }
  }
}

///|
test "DATA imports only used inputs and preserves input and Stage budgets" {
  let context = fixture_context()
  let extra = {
    ..context.inputs[0],
    name: "unused",
    relation: [{ value: "unused", quoted: false, }],
  }
  let script = @query.parse_query_script(
    "DATA kept = FROM orders |> SELECT id; FROM kept |> SELECT id",
    syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    {
      ..context,
      inputs: [context.inputs[0], extra],
      captured_stage: Some("capture"),
    },
    construction_limits(),
  ).unwrap()
  assert_false(semantic(program).contains("unused"))
  assert_eq(@program.stage_count(program), 2)
  assert_true(
    compile_query_script(
      script,
      { ..context, captured_stage: Some("capture"), },
      {
        ..construction_limits(),
        program: { ..construction_limits().program, max_stages: 1, },
      },
    )
    is Err(Admission(_)),
  )
  for
    bad in [
      { ..context, captured_stage: Some(""), },
      { ..context, captured_stage: Some("main"), },
      { ..context, inputs: [context.inputs[0], context.inputs[0]], },
      { ..context, inputs: [{ ..context.inputs[0], visible_fields: ["id"], }], },
      {
        ..context,
        inputs: [
          { ..context.inputs[0], source: StageResult("missing", "rows"), },
        ],
      },
    ] {
    assert_true(
      compile_query_script(script, bad, construction_limits())
      is Err(InvalidContext),
    )
  }
}

///|
test "DATA capture preserves published Relation names and DATA alias names" {
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    text in [
      "DATA g = PROPERTY GRAPH (NODE TABLES (`orders` AS Person KEY (id) LABEL Person PROPERTIES (id), `orders` AS Company KEY (id) LABEL Company PROPERTIES (id))); FROM GRAPH g |> MATCH (a:Person) |> SELECT a.id",
      "DATA saved = FROM orders |> SELECT id; DATA g = PROPERTY GRAPH (NODE TABLES (saved AS Person KEY (id) LABEL Person PROPERTIES (id), `SAVED` AS Company KEY (id) LABEL Company PROPERTIES (id))); FROM GRAPH g |> MATCH (a:Person) |> SELECT a.id",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(@program.stage_count(program), 2)
    assert_eq(semantic(program).split("\"carrier\":\"relation\"").length(), 2)
  }
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        "DATA g = PROPERTY GRAPH (NODE TABLES (orders AS Person KEY (id) LABEL Person PROPERTIES (id), `ORDERS` AS Company KEY (id) LABEL Company PROPERTIES (id))); FROM GRAPH g |> MATCH (a:Person) |> SELECT a.id",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    )
    is Err(UnknownRelation),
  )
}
