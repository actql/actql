///|
fn graph_union_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","union_graphs":{"with":["aql_data_2","aql_data_2"],"merge":{"node_properties":{"p":"number_sum"}}},"as":"aql_sga_3"},{"from":"aql_sga_3","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn check_graph_union_source(program : @program.Program) -> Unit raise {
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
    NeedsInputs(_) => fail("Graph composition reuses its DATA producers")
  }
}

///|
fn graph_union_prefix() -> String {
  "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); "
}

///|
test "Graph union source preserves repeated peers and policy in independent Program" {
  let expected = graph_union_expected()
  check_graph_union_source(expected)
  let actual = compile_data_set(
    graph_union_prefix() +
    "FROM g |> union_graphs(with: [g, g], merge: {node_properties: {p: 'number_sum'}}) |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(expected))
  check_graph_union_source(actual)
}

///|
test "Graph union DATA and chained row entry retain producer names" {
  let program = compile_data_set(
    graph_union_prefix() +
    "DATA `peer graph` = FROM g; DATA doubled = FROM g |> union_graphs(with: `peer graph`, merge: {node_properties: {p: 'number_sum'}}); FROM g |> union_graphs(with: [doubled, g], merge: {node_properties: {p: 'number_mean'}}) |> node_rows(definition: 'N') |> SELECT p, node_key",
  )
  check_graph_union_source(program)
  let body = semantic(program)
  assert_eq(body.split("\"property_graph\":").length(), 2)
  assert_eq(body.split("\"union_graphs\":").length(), 3)
  assert_true(body.contains("\"with\":[\"aql_sga_5\",\"aql_data_2\"]"))
  assert_true(body.contains("\"node_properties\":{\"p\":\"number_mean\"}"))
}

///|
test "Graph union rejects value names forward references and lost Graph scopes" {
  for
    suffix in [
      "FROM g |> union_graphs(with: 'g') |> node_rows()", "FROM g |> union_graphs(with: [g, 1]) |> node_rows()",
    ] {
    assert_true(
      @query.parse_query_script(graph_union_prefix() + suffix, syntax_limits())
      is Err({ issue: @query.Syntax(_), .. }),
      msg=suffix,
    )
  }
  for
    suffix in [
      "FROM g |> union_graphs(with: []) |> node_rows()", "FROM g |> union_graphs() |> node_rows()",
      "FROM g |> union_graphs(with: g, extra: true) |> node_rows()", "FROM g |> node_rows() |> union_graphs(with: g)",
    ] {
    let query = @query.parse_query_script(
      graph_union_prefix() + suffix,
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        query,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedGraph),
      msg=suffix,
    )
  }
  for
    suffix in [
      "FROM g |> union_graphs(with: missing) |> node_rows()", "FROM g |> union_graphs(with: n) |> node_rows()",
      "DATA h = FROM g |> union_graphs(with: later); DATA later = FROM g; FROM h |> node_rows()",
    ] {
    let query = @query.parse_query_script(
      graph_union_prefix() + suffix,
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        query,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnknownRelation),
      msg=suffix,
    )
  }
}

///|
test "Graph union passes policy validation to the common checker" {
  for
    policy in [
      "{node_properties: {p: 'unknown'}}", "{node_properties: {missing: 'number_sum'}}",
      "{extra: true}",
    ] {
    let program = compile_data_set(
      graph_union_prefix() +
      "FROM g |> union_graphs(with: g, merge: " +
      policy +
      ") |> node_rows() |> SELECT p",
    )
    assert_true(
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      is Rejected(_),
      msg=policy,
    )
  }
}

///|
test "public union JSON control has checked composite keys parallel edges and both Results" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.graph_union","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"part":{"type":"number","nullable":false},"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"part":7,"node_key":1,"p":7}]},"as":"n"},{"values":{"schema":{"part":{"type":"number","nullable":false},"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"w":{"type":"number","nullable":false}},"rows":[{"part":7,"edge_key":11,"src_key":1,"dst_key":1,"w":5},{"part":7,"edge_key":10,"src_key":1,"dst_key":1,"w":2}]},"as":"e"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["part","node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["part","edge_key"],"source":{"definition":"N","key":["part","src_key"]},"target":{"definition":"N","key":["part","dst_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"w","to":"w"}]}}]}]},"as":"g"},{"from":"g","union_graphs":{"with":["g","g"],"merge":{"node_properties":{"p":"number_sum"},"edge_properties":{"w":"number_sum"}}},"as":"combined"},{"from":"combined","node_rows":true,"as":"nodes"},{"from":"nodes","select":["p","part","node_key","labels"],"as":"node_projection"},{"from":"combined","edge_rows":true},{"select":["w","part","edge_key","labels"]},{"sort":[{"field":"edge_key","dir":"asc","nulls":"first"}],"as":"edge_projection"}],"results":{"nodes":{"from":"node_projection","fields":["p","part","node_key","labels"]},"edges":{"from":"edge_projection","fields":["w","part","edge_key","labels"]}}}],"results":{"nodes":{"from":{"stage":"main","result":"nodes"}},"edges":{"from":{"stage":"main","result":"edges"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_graph_union_source(control)
}

///|
test "complete public edge union source has one query and passes ordinary checker" {
  let program = compile_data_set(
    "DATA n = SELECT 7 AS part, 1 AS node_key, 7 AS p; DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); DATA combined = FROM g |> union_graphs(with: [g, g], merge: {node_properties: {p: 'number_sum'}, edge_properties: {w: 'number_sum'}}); FROM combined |> edge_rows() |> SELECT w, part, edge_key, labels |> ORDER BY edge_key |> RESULT edges",
  )
  check_graph_union_source(program)
  assert_true(semantic(program).contains("\"union_graphs\""))
}
