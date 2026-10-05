///|
fn graph_equality_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","graphs_equal":{"with":"aql_data_2"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["equal"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["equal"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
  let actual = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); FROM g |> graphs_equal(with: g) |> SELECT equal",
  )
  assert_eq(semantic(actual), semantic(graph_equality_expected()))
}

///|
test "Graph equality DATA resolves quoted aliases without copying the Graph" {
  let program = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); DATA `peer graph` = FROM g; DATA same = FROM g |> normalize_graph() |> graphs_equal(with: `peer graph`); FROM same |> WHERE equal |> SELECT equal",
  )
  let body = semantic(program)
  assert_eq(body.split("\"property_graph\":").length(), 2)
  assert_eq(body.split("\"graphs_equal\":").length(), 2)
  assert_true(body.contains("\"normalize_graph\":true"))
  assert_true(body.contains("\"graphs_equal\":{\"with\":\"aql_data_2\"}"))
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
test "Graph equality retains ORDER and LIMIT at the common unresolved boundary" {
  let actual = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); FROM g |> graphs_equal(with: g) |> SELECT equal |> ORDER BY equal |> LIMIT 1",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","graphs_equal":{"with":"aql_data_2"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["equal"]},{"sort":[{"field":"equal","dir":"asc","nulls":"first"}]},{"take":{"count":1,"offset":0},"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["equal"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    guard checked is Rejected(diagnostic) else {
      fail("ordered comparison remains a separate common-owner gap")
    }
    assert_true(
      @check.diagnostic_cause(diagnostic)
      is Source(
        SourceView(
          Program(
            Program(
              Order(_, PipelineOrder({ kind: @pipeline.UnresolvedOrder, .. }))
            )
          )
        )
      ),
    )
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
    "DATA same = FROM g |> graphs_equal(with: later); DATA later = FROM g; FROM same |> SELECT equal",
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
      assert_true(result is Err(UnknownColumn), msg=suffix)
    } else {
      assert_true(result is Err(UnsupportedGraph), msg=suffix)
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
