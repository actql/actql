///|
fn graph_difference_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","graph_diff":{"with":"aql_data_2"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["delta"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["delta"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn graph_difference_normally_checked(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => {
      assert_true(
        @check.diagnostic_cause(diagnostic)
        is Source(
          SourceView(
            Program(
              Program(Order(0, ResultOrder({ kind: UnresolvedOrder, .. })))
            )
          )
        ),
      )
      fail("checked Graph difference must retain common publication order")
    }
    NeedsInputs(_) => fail("Graph difference requires no extra acquisition")
  }
}

///|
test "Graph difference independent Program uses the common publication owner" {
  graph_difference_normally_checked(graph_difference_expected())
}

///|
test "Graph difference source preserves its independently authored Program" {
  let program = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); FROM g |> graph_diff(with: g) |> SELECT delta",
  )
  assert_eq(semantic(program), semantic(graph_difference_expected()))
  graph_difference_normally_checked(program)
}

///|
test "Graph difference DATA aliases retain existing producers and Relation scope" {
  let program = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); DATA `peer graph` = FROM g; DATA changes = FROM g |> normalize_graph() |> graph_diff(with: `peer graph`); FROM changes |> SELECT delta",
  )
  let body = semantic(program)
  assert_eq(body.split("\"property_graph\":").length(), 2)
  assert_eq(body.split("\"graph_diff\":").length(), 2)
  assert_true(body.contains("\"normalize_graph\":true"))
  assert_true(body.contains("\"graph_diff\":{\"with\":\"aql_data_2\"}"))
  assert_true(body.contains("\"fields\":[\"delta\"]"))
  graph_difference_normally_checked(program)
}

///|
test "Graph difference rejects unknown Relation and forward producer references" {
  for
    suffix in [
      "FROM g |> graph_diff(with: missing) |> SELECT delta", "FROM g |> graph_diff(with: n) |> SELECT delta",
      "DATA changes = FROM g |> graph_diff(with: later); DATA later = FROM g; FROM changes |> SELECT delta",
    ] {
    let script = @query.parse_query_script(
      graph_rows_prefix() + suffix,
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnknownRelation),
      msg=suffix,
    )
  }
}

///|
test "Graph difference rejects hidden Graph columns and repeated transitions" {
  for
    suffix in [
      "FROM g |> graph_diff() |> SELECT delta", "FROM g |> graph_diff(with: g, extra: true) |> SELECT delta",
      "FROM g |> graph_diff(with: g) |> node_rows() |> SELECT delta", "FROM g |> node_rows() |> graph_diff(with: g) |> SELECT delta",
      "FROM g |> graph_diff(with: g) |> SELECT node_key",
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
test "Graph difference does not reinterpret a string as a producer reference" {
  assert_true(
    @query.parse_query_script(
      graph_rows_prefix() + "FROM g |> graph_diff(with: 'g') |> SELECT delta",
      syntax_limits(),
    )
    is Err(_),
  )
}
