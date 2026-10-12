///|
fn graph_event_continuation(text : String) -> @program.Program raise {
  match with_carrier_program(text, { ..pair_context(), inputs: [], }) {
    Ok(program) => program
    Err(InvalidQuery) => fail("Actual InvalidQuery discarded a supported Events tail")
    Err(_) => fail("The existing Graph row and Events owners must receive the full tail")
  }
}

///|
fn graph_event_environment() -> @check.CheckEnvironment {
  @check.checking_environment(
    @check.checking_environment_wire(graph_rows_environment()),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
    graph=true,
    numeric_profile=Some(@numeric.builtin_profile()),
  )
}

///|
// The control is handwritten from the Graph mapping and Events contracts;
// operation arguments must agree despite generated producer-name differences.
fn graph_event_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.graph_events","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"occurred_ms":{"type":"number","nullable":false}},"rows":[{"node_key":1,"occurred_ms":0}]},"as":"rows"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"rows","key":["node_key"],"labels":[{"name":"N","properties":{"mode":"columns","columns":[{"from":"node_key","to":"node_key"},{"from":"occurred_ms","to":"occurred_ms"}]}}]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"nodes"},{"from":"nodes","to_events":{"id":"node_key","time":"occurred_ms"},"as":"ev"},{"from":"ev","events":true,"as":"event_rows"},{"from":"event_rows","select":["node_key","occurred_ms"],"as":"out"}],"results":{"rows":{"from":"out","fields":["node_key","occurred_ms"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph node rows preserve a flat Events tail" {
  let prefix = "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (node_key, occurred_ms)))) "
  let actual = graph_event_continuation(
    prefix + "FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms",
  )
  let control = graph_event_control()
  for operation in ["node_rows", "to_events", "events"] {
    assert_eq(with_carrier_argument(actual, operation), with_carrier_argument(control, operation))
  }
  guard @check.check_parsed_with_evidence(actual, graph_event_environment(), None, [], graph_rows_check_limits()) is Checked(_) else {
    fail("the unchanged common owners must check the complete Graph/Events tail")
  }
}

///|
test "Graph row bridge and intermediate WITH keep the same Events operations" {
  let prefix = "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (node_key, occurred_ms)))), "
  let actual = graph_event_continuation(
    prefix + "event_values AS (FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms)), event_rows AS (FROM event_values |> events()) SELECT node_key, occurred_ms FROM event_rows",
  )
  let control = graph_event_control()
  for operation in ["node_rows", "to_events", "events"] {
    assert_eq(with_carrier_argument(actual, operation), with_carrier_argument(control, operation))
  }
}
