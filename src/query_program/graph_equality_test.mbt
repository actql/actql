///|
fn graph_equality_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","graphs_equal":{"with":"aql_with_graph_2"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["equal"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["equal"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph equality independent Program uses the ordinary checker" {
  match
    @check.check_parsed_with_evidence(
      graph_equality_expected(),
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_equality_rejected(diagnostic)
    NeedsInputs(_) => fail("Graph equality adds no acquisition")
  }
}

///|
test "Graph equality source matches its independent complete Program" {
  let actual = compile_with_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) FROM g |> graphs_equal(with: g) |> SELECT equal",
  )
  assert_eq(semantic(actual), semantic(graph_equality_expected()))
}

///|
test "Graph equality WITH resolves quoted aliases without copying the Graph" {
  let program = compile_with_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))))  , `peer graph` AS (FROM g), same AS (FROM g |> normalize_graph() |> graphs_equal(with: `peer graph`)) FROM same |> WHERE equal |> SELECT equal",
  )
  let body = semantic(program)
  assert_eq(body.split("\"graph\":").length(), 2)
  assert_eq(body.split("\"graphs_equal\":").length(), 2)
  assert_true(body.contains("\"normalize_graph\":true"))
  assert_true(body.contains("\"graphs_equal\":{\"with\":\"aql_with_graph_2\"}"))
  assert_true(body.contains("\"fields\":[\"equal\"]"))
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_equality_rejected(diagnostic)
    NeedsInputs(_) => fail("Graph alias comparison adds no acquisition")
  }
}

///|
test "Graph equality singleton supports ORDER and LIMIT through the common owner" {
  let actual = compile_with_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) FROM g |> graphs_equal(with: g) |> SELECT equal |> ORDER BY equal |> LIMIT 1",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","graphs_equal":{"with":"aql_with_graph_2"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["equal"]},{"sort":[{"field":"equal","dir":"asc","nulls":"first"}]},{"take":{"count":1,"offset":0},"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["equal"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for program in [actual, expected] {
    let checked = @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    )
    match checked {
      Checked(_) => ()
      Rejected(diagnostic) => graph_equality_rejected(diagnostic)
      NeedsInputs(_) => fail("ordered equality needs no acquisition")
    }
  }
}

///|
fn graph_equality_rejected(diagnostic : @check.CheckDiagnostic) -> Unit raise {
  match @check.diagnostic_cause(diagnostic) {
    Source(SourceView(Program(Program(Order(_, PipelineOrder(issue)))))) =>
      fail(@debug.to_string(issue.kind))
    Source(SourceView(Program(Program(Order(_, ProducerOrder(issue)))))) =>
      fail(@debug.to_string(issue.issue.kind))
    Source(SourceView(Program(Program(Order(_, ResultOrder(issue)))))) =>
      fail(@debug.to_string(issue.kind))
    _ => graph_rows_rejected(diagnostic)
  }
}

///|
test "Graph equality rejects unknown or Relation producer references" {
  for name in ["missing", "n"] {
    let script = @query.parse_query_script(
      graph_rows_prefix() +
      "FROM g |> graphs_equal(with: " +
      name +
      ") |> SELECT equal",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnknownRelation),
      msg=name,
    )
  }
  let forward = @query.parse_query_script(
    graph_rows_prefix() +
    " , same AS (FROM g |> graphs_equal(with: later)), later AS (FROM g) FROM same |> SELECT equal",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      forward,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnknownRelation),
  )
}

///|
test "Graph equality rejects unknown arguments and repeated Carrier transitions" {
  for
    suffix in [
      "FROM g |> graphs_equal() |> SELECT equal", "FROM g |> graphs_equal(with: g, extra: true) |> SELECT equal",
      "FROM g |> graphs_equal(with: g) |> node_rows() |> SELECT equal", "FROM g |> node_rows() |> graphs_equal(with: g) |> SELECT equal",
      "FROM g |> graphs_equal(with: g) |> SELECT node_key",
    ] {
    let script = @query.parse_query_script(
      graph_rows_prefix() + suffix,
      syntax_limits(),
    ).unwrap()
    let result = compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    if suffix.has_suffix("SELECT node_key") {
      guard result
        is Err(
          Expression(
            { issue: @expression.UnknownReference, origin: Some(origin), }
          )
        ) else {
        fail("the Relation output must reject the old Graph column: " + suffix)
      }
      assert_eq(@origin.kind(origin), @origin.Authored)
      let span = @origin.span(origin)
      assert_eq(span.start_byte, 473)
      assert_eq(span.end_byte, 481)
    } else {
      assert_true(result is Err(InvalidQuery), msg=suffix)
    }
  }
}

///|
test "Graph equality does not reinterpret a string as a producer reference" {
  assert_true(
    @query.parse_query_script(
      graph_rows_prefix() + "FROM g |> graphs_equal(with: 'g') |> SELECT equal",
      syntax_limits(),
    )
    is Err(_),
  )
}
