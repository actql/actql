///|
fn graph_rows_join_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.graph_rows_join","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"node_key":1,"p":7}]},"as":"nodes"},{"values":{"schema":{"tag":{"type":"number","nullable":false}},"rows":[{"tag":2}]},"as":"rights"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"rows"},{"from":"rows","cross_join":{"with":"rights","max_output_rows":10,"select":{"value":"left.p","tag":"right.tag"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["value","tag"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph rows join prefix reuses the existing Relation join owner" {
  let expected = graph_rows_join_control()
  match
    @check.check_parsed_with_evidence(
      expected,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("independent Graph row JOIN needs no acquisition")
  }
  let source = "DATA n = SELECT 1 AS node_key, 7 AS p; DATA r = SELECT 2 AS tag; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); FROM g |> node_rows() |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l.p AS value, rr.tag AS tag"
  let actual = compile_with_set(source)
  match
    @check.check_parsed_with_evidence(
      actual,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("Graph row JOIN must not add acquisition")
  }
  let body = semantic(actual)
  assert_eq(body.split("\"node_rows\":true").length(), 2)
  assert_true(body.contains("\"max_output_rows\":10"))
  assert_true(
    body.contains("\"select\":{\"tag\":\"right.tag\",\"value\":\"left.p\"}"),
  )
  assert_true(body.contains("\"fields\":[\"value\",\"tag\"]"))
}

///|
test "Graph row bindings pass through authored CTE and edge JOIN prefixes" {
  for
    source in [
      graph_rows_prefix() +
      "DATA r = SELECT 10 AS key; FROM g |> edge_rows(definition: 'E') |> SELECT edge_key |> AS l |> JOIN r AS rr ON l.edge_key = rr.key MAX_OUTPUT_ROWS 10 |> SELECT l.edge_key, rr.key |> ORDER BY edge_key",
      graph_rows_prefix() +
      "DATA r = SELECT 1 AS key; WITH picked AS (FROM g |> node_rows(definition: 'N') |> SELECT node_key) SELECT l.node_key, rr.key FROM picked AS l JOIN r AS rr ON l.node_key = rr.key MAX_OUTPUT_ROWS 10 ORDER BY node_key",
      graph_rows_prefix() +
      "DATA r = SELECT 1 AS key; DATA picked = FROM g |> node_rows() |> WHERE node_key > 0 |> AS l |> JOIN r AS rr ON l.node_key = rr.key MAX_OUTPUT_ROWS 10 |> SELECT l.node_key, rr.key; FROM picked |> ORDER BY node_key",
    ] {
    let actual = compile_with_set(source)
    match
      @check.check_parsed_with_evidence(
        actual,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("Graph rows may not add acquisition")
    }
    assert_true(semantic(actual).contains("\"max_output_rows\":10"))
  }
}

///|
test "Graph row JOIN cannot revive removed fields or a shadowed Graph binding" {
  let prefix = graph_rows_prefix() + "DATA r = SELECT 1 AS key; "
  for
    source in [
      prefix +
      "FROM g |> node_rows() |> SELECT node_key |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l.name",
      prefix +
      "FROM g |> node_rows() |> SELECT node_key |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT g.node_key",
      prefix +
      "WITH g AS (SELECT 1 AS id) FROM g |> node_rows() |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l.node_key",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(AmbiguousColumn) | Err(UnknownColumn) | Err(UnsupportedGraph) => ()
      _ =>
        fail(
          "removed row fields or shadowed Graph must remain rejected: " + source,
        )
    }
  }
  for operation in ["normalize_graph()", "reach(start: 'A', max_depth: 1)"] {
    let source = prefix +
      "FROM g |> " +
      operation +
      " |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT rr.key"
    assert_true(
      @query.parse_query_script(source, syntax_limits()) is Err(_),
      msg=source,
    )
  }
}
