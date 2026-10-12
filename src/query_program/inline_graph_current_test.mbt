///|
fn carrier_primary_event_environment() -> @check.CheckEnvironment {
  @check.checking_environment(
    @check.checking_environment_wire(graph_rows_environment()),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
    graph=true,
    numeric_profile=Some(@numeric.builtin_profile()),
  )
}

///|
// Handwritten common Program controls do not depend on generated names or
// the text lowerer's output. The original typed key/property roles are exact.
fn carrier_primary_control(events : Bool) -> @program.Program {
  let source = if events {
    (
      #|{"version":"actql/0.1","id":"fixture.primary_events","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"occurred_ms":{"type":"number","nullable":false}},"rows":[{"node_key":1,"occurred_ms":0}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"N","properties":{"mode":"columns","columns":[{"from":"occurred_ms","to":"occurred_ms"}]}}]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"nodes"},{"from":"nodes","to_events":{"id":"node_key","time":"occurred_ms"},"as":"ev"},{"from":"ev","events":true,"as":"rows"},{"from":"rows","select":["node_key","occurred_ms"],"as":"answer"}],"results":{"rows":{"from":"answer","fields":["node_key","occurred_ms"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"fixture.primary_rows","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"node_key":1,"p":7}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"N","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"nodes"},{"from":"nodes","select":["p","node_key"],"as":"answer"}],"results":{"rows":{"from":"answer","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    )
  }
  @program.parse(source, construction_limits().program, format=Json).unwrap()
}

///|
fn carrier_current_primary_program(source : String) -> @program.Program raise {
  match
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnknownColumn) =>
      fail("the original Graph-row input was replaced by a source-free Unit")
    Err(UnsupportedGraph) => fail("UnsupportedGraph at the original primary")
    Err(InvalidContext) => fail("InvalidContext at the original primary")
    Err(InvalidQuery) => fail("InvalidQuery at the original primary")
    Err(UnsupportedProjection) =>
      fail("UnsupportedProjection at the original primary")
    Err(UnknownRelation) => fail("UnknownRelation at the original primary")
    Err(issue) => with_demand_program(Err(issue))
  }
}

///|
test "a direct Graph primary keeps its actual row producer for Relation continuation" {
  let program = carrier_current_primary_program(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p) GRAPH (NODE TABLES (n AS N KEY (node_key) PROPERTIES (p))) |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(program).split("\"node_rows\":").length() - 1, 1)
  assert_eq(semantic(program).split("\"values\":{").length() - 1, 1)
  assert_eq(
    with_carrier_argument(program, "node_rows"),
    with_carrier_argument(carrier_primary_control(false), "node_rows"),
  )
  for program in [program, carrier_primary_control(false)] {
    match
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("the original Graph primary has no acquisition")
    }
  }
}

///|
test "a direct Graph primary keeps its current slot through an Events bridge" {
  let program = carrier_current_primary_program(
    "WITH n AS (SELECT 1 AS node_key, 0 AS occurred_ms) GRAPH (NODE TABLES (n AS N KEY (node_key) PROPERTIES (occurred_ms))) |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms",
  )
  let body = semantic(program)
  assert_eq(body.split("\"values\":{").length() - 1, 1)
  for operation in ["node_rows", "to_events", "events"] {
    assert_eq(body.split("\"" + operation + "\":").length() - 1, 1)
    assert_eq(
      with_carrier_argument(program, operation),
      with_carrier_argument(carrier_primary_control(true), operation),
    )
  }
  for program in [program, carrier_primary_control(true)] {
    match
      @check.check_parsed_with_evidence(
        program,
        carrier_primary_event_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("the original Carrier bridge has no acquisition")
    }
  }
}

///|
test "ordinary source-free SELECT keeps its Unit with unrelated lexical inputs" {
  let program = with_carrier_program(
    "SELECT 1 AS only_value",
    nearest_context(),
  ).unwrap()
  let body = semantic(program)
  assert_eq(body.split("\"values\":{").length() - 1, 1)
  assert_true(body.contains("\"aql_source_free_unit\""))
  assert_true(body.contains("\"literal\":1"))
  assert_false(body.contains("\"request_id\""))
  assert_false(body.contains("\"embedding\""))
  assert_false(body.contains("\"candidates\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("the unchanged source-free Unit has no acquisition")
  }
}

///|
test "an inline Graph row star exposes its actual fields without a private range" {
  let prefix = "WITH n AS (SELECT 1 AS node_key, 7 AS p) GRAPH (NODE TABLES (n AS N KEY (node_key) PROPERTIES (p))) |> node_rows()"
  let program = carrier_current_primary_program(prefix + " |> SELECT *")
  assert_true(
    semantic(program).contains(
      "\"fields\":[\"id\",\"labels\",\"node_key\",\"p\"]",
    ),
  )
  assert_eq(semantic(program).split("\"values\":{").length() - 1, 1)
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        prefix + " |> SELECT aql_sga_3.p",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}
