///|
test "independent common Subgraph control is already checked" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.subgraph","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"node_key":1,"p":7}]},"as":"n"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"selected"},{"from":"g","subgraph":{"nodes":{"from":"selected","id":"id"}},"as":"slice"},{"from":"slice","node_rows":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["node_key","p"]}}}],"results":{"answer":{"from":{"stage":"main","result":"out"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
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
    NeedsInputs(_) => fail("The common Subgraph control has no external input")
  }
}

///|
test "Subgraph source preserves its Relation selector in an independent complete Program" {
  let actual = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); DATA selected = FROM g |> node_rows() |> SELECT id; DATA slice = FROM g |> subgraph(nodes: {from: selected, id: 'id'}); FROM slice |> node_rows() |> SELECT p, node_key",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":["id"],"as":"aql_data_3"},{"from":"aql_data_2","subgraph":{"nodes":{"from":"aql_data_3","id":"id"}},"as":"aql_sga_6"},{"from":"aql_sga_6","node_rows":true,"as":"aql_sga_7"},{"from":"aql_sga_7","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
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
    NeedsInputs(_) => fail("The selector reuses its emitted producer")
  }
}

///|
test "Subgraph source preserves predicates across inline, DATA and MATCH boundaries" {
  let prefix = graph_rows_prefix() +
    "DATA selected = FROM g |> node_rows() |> WHERE node_key = 1 |> SELECT id; "
  for
    suffix in [
      "FROM g |> subgraph(nodes: {from: selected, id: 'id'}, edges: {literal: false}) |> node_rows() |> SELECT node_key, name",
      "DATA `slice` = FROM g |> normalize_graph() |> subgraph(nodes: {from: selected, id: 'id'}); FROM `slice` |> edge_rows() |> SELECT edge_key",
      "FROM GRAPH g |> subgraph(nodes: {from: selected, id: 'id'}) |> MATCH WALK (a:Node) |> SELECT a.name",
    ] {
    let actual = compile_data_set(prefix + suffix)
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
      NeedsInputs(_) => fail("Subgraph adds no acquisition")
    }
  }
}

///|
test "Subgraph source retains malformed and unadapted bodies for common refusal" {
  for
    call in [
      "subgraph()", "subgraph(nodes: {ids: []})", "subgraph(nodes: {from: selected, id: 'missing'})",
      "subgraph(nodes: {from: selected, id: 'node_key'})", "subgraph(nodes: {from: selected, id: 'id'}, edges: {literal: 1})",
      "subgraph(nodes: {from: selected, id: 'id'}, extra: true)",
      // The adopted where selector is a separate common support gap. Keep its
      // authored expression and let that owner reject it before admission.
       "subgraph(nodes: {where: {literal: true}})",
    ] {
    let actual = compile_data_set(
      graph_rows_prefix() +
      "DATA selected = FROM g |> node_rows() |> SELECT id, node_key; FROM g |> " +
      call +
      " |> node_rows() |> SELECT node_key",
    )
    assert_true(
      @check.check_parsed_with_evidence(
        actual,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      is Rejected(_),
      msg=call,
    )
  }
}

///|
test "Subgraph source keeps producer references and Carrier transitions scoped" {
  for
    suffix in [
      "FROM g |> subgraph(nodes: {from: missing, id: 'id'}) |> node_rows() |> SELECT node_key",
      "DATA slice = FROM g |> subgraph(nodes: {from: later, id: 'id'}); DATA later = FROM g |> node_rows(); FROM slice |> node_rows() |> SELECT node_key",
      "FROM g |> subgraph(nodes: {from: g, id: 'id'}) |> node_rows() |> SELECT node_key",
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
  let script = @query.parse_query_script(
    graph_rows_prefix() +
    "FROM g |> node_rows() |> subgraph(nodes: {ids: []}) |> SELECT node_key",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnsupportedGraph),
  )
}
