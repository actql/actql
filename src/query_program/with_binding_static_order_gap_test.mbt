///|
test "check-only WITH capture gap is Result order closure, not pipeline typing" {
  // Independently authored minimal Program. The unused capture publishes a
  // nullable object column, but the only public export is one numeric row.
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.with_static_order_gap","stages":[{"id":"capture","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"objects","filter":{"literal":true}},{"select":["id","payload"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id","payload"]}}},{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let source = @stage_parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let context = source_member_context(captured=true)
  let (views, locals) = @check_context.prepare_source_registrations(
    source,
    context.source_catalog.unwrap(),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
    max_inputs=100,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let result = @check_context.prepare_sourceview_program(views, locals, {
    max_stages: 20,
    max_steps: 100,
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  })
  // Freeze the actual current API boundary. This is not a permanent language
  // restriction or successful unused-binding acceptance; the conditional
  // check-only common API must eventually retain this unresolved obligation.
  guard result is Err(Program(Order(0, ResultOrder(issue)))) else {
    fail("expected exact common Result-order preparation boundary")
  }
  assert_eq(issue.kind, @relation_results.UnresolvedOrder)
  assert_eq(@wire.cursor_path(issue.source), [
    Key("stages"),
    Index(0),
    Key("results"),
    Key("source"),
  ])
}

///|
test "demanded WITH capture still requires ordinary publication order" {
  let parsed = @query.parse_query_script(
    "WITH kept AS (SELECT id, payload FROM objects) SELECT id, payload FROM kept",
    syntax_limits(),
  ).unwrap()
  guard compile_query_script(parsed, source_member_context(captured=true), construction_limits())
    is Err(BindingPreparation(SourceProgram(Program(Order(0, ResultOrder(issue)))))) else {
    fail("demanded capture must not receive a fabricated publication order")
  }
  assert_eq(issue.kind, @relation_results.UnresolvedOrder)
  assert_eq(@wire.cursor_path(issue.source), [Key("stages"), Index(0), Key("results"), Key("source")])
}

///|
test "unused WITH LIMIT cannot defer its required input order" {
  let parsed = @query.parse_query_script(
    "WITH unused AS (FROM objects |> LIMIT 1) SELECT 1 AS id",
    syntax_limits(),
  ).unwrap()
  guard compile_query_script(parsed, source_member_context(captured=true), construction_limits())
    is Err(BindingPreparation(SourceProgram(Program(Order(1, PipelineOrder(issue)))))) else {
    fail("unused LIMIT still requires original input order")
  }
  assert_eq(issue.kind, @pipeline.UnresolvedOrder)
}
