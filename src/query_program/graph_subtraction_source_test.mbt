///|
fn graph_subtraction_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","subtract_graphs":{"with":"aql_data_2","merge":{"node_properties":{"p":"number_sum"}}},"as":"aql_sga_3"},{"from":"aql_sga_3","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph subtraction source retains its binary peer and policy in independent Program" {
  let expected = graph_subtraction_expected()
  check_graph_union_source(expected)
  let actual = compile_data_set(
    graph_union_prefix() +
    "FROM g |> subtract_graphs(with: g, merge: {node_properties: {p: 'number_sum'}}) |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(expected))
  check_graph_union_source(actual)
}

///|
test "Graph subtraction resolves quoted DATA peers without turning values into names" {
  let program = compile_data_set(
    graph_union_prefix() +
    "DATA `peer graph` = FROM g; DATA remaining = FROM g |> subtract_graphs(with: `peer graph`, merge: {node_properties: {p: 'exact_equal'}}); FROM remaining |> node_rows() |> SELECT p, node_key",
  )
  check_graph_union_source(program)
  let body = semantic(program)
  assert_true(body.contains("\"with\":\"aql_data_2\""))
  assert_true(body.contains("\"subtract_graphs\":"))
  assert_true(body.contains("\"node_properties\":{\"p\":\"exact_equal\"}"))
  assert_eq(body.split("\"property_graph\":").length(), 2)
}

///|
test "Graph subtraction enforces binary peers and retained Graph scope" {
  for
    suffix in [
      "FROM g |> subtract_graphs(with: [g]) |> node_rows()", "FROM g |> subtract_graphs(with: []) |> node_rows()",
      "FROM g |> subtract_graphs() |> node_rows()", "FROM g |> subtract_graphs(with: g, extra: true) |> node_rows()",
      "FROM g |> node_rows() |> subtract_graphs(with: g)",
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
      "FROM g |> subtract_graphs(with: missing) |> node_rows()", "FROM g |> subtract_graphs(with: n) |> node_rows()",
      "DATA h = FROM g |> subtract_graphs(with: later); DATA later = FROM g; FROM h |> node_rows()",
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
  assert_true(
    @query.parse_query_script(
      graph_union_prefix() +
      "FROM g |> subtract_graphs(with: 'g') |> node_rows()",
      syntax_limits(),
    )
    is Err({ issue: @query.Syntax(_), .. }),
  )
}

///|
test "independent subtraction JSON controls preserve removal and shared-Graph outputs" {
  let control = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.graph_subtraction\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"part\":{\"type\":\"number\",\"nullable\":false},\"node_key\":{\"type\":\"number\",\"nullable\":false},\"p\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"part\":7,\"node_key\":1,\"p\":7}]},\"as\":\"n\"},{\"values\":{\"schema\":{\"part\":{\"type\":\"number\",\"nullable\":false},\"edge_key\":{\"type\":\"number\",\"nullable\":false},\"src_key\":{\"type\":\"number\",\"nullable\":false},\"dst_key\":{\"type\":\"number\",\"nullable\":false},\"w\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"part\":7,\"edge_key\":11,\"src_key\":1,\"dst_key\":1,\"w\":5},{\"part\":7,\"edge_key\":10,\"src_key\":1,\"dst_key\":1,\"w\":2}]},\"as\":\"e\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"n\",\"key\":[\"part\",\"node_key\"],\"labels\":[{\"name\":\"Person\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"p\",\"to\":\"p\"}]}}]}],\"edges\":[{\"name\":\"E\",\"from\":\"e\",\"key\":[\"part\",\"edge_key\"],\"source\":{\"definition\":\"N\",\"key\":[\"part\",\"src_key\"]},\"target\":{\"definition\":\"N\",\"key\":[\"part\",\"dst_key\"]},\"labels\":[{\"name\":\"R\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"w\",\"to\":\"w\"}]}}]}]},\"as\":\"g\"},{\"from\":\"g\",\"subtract_graphs\":{\"with\":\"g\",\"merge\":{\"node_properties\":{\"p\":\"number_sum\"},\"edge_properties\":{\"w\":\"number_sum\"}}},\"as\":\"combined\"},{\"from\":\"combined\",\"node_rows\":true,\"as\":\"nodes\"},{\"from\":\"nodes\",\"select\":[\"p\",\"part\",\"node_key\",\"labels\"],\"as\":\"node_projection\"},{\"from\":\"combined\",\"edge_rows\":true},{\"select\":[\"w\",\"part\",\"edge_key\",\"labels\"]},{\"sort\":[{\"field\":\"edge_key\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"edge_projection\"}],\"results\":{\"nodes\":{\"from\":\"node_projection\",\"fields\":[\"p\",\"part\",\"node_key\",\"labels\"]},\"edges\":{\"from\":\"edge_projection\",\"fields\":[\"w\",\"part\",\"edge_key\",\"labels\"]}}}],\"results\":{\"nodes\":{\"from\":{\"stage\":\"main\",\"result\":\"nodes\"}},\"edges\":{\"from\":{\"stage\":\"main\",\"result\":\"edges\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_graph_union_source(control)
  let control = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.graph_subtraction_subset\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"part\":{\"type\":\"number\",\"nullable\":false},\"node_key\":{\"type\":\"number\",\"nullable\":false},\"p\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"part\":7,\"node_key\":1,\"p\":7},{\"part\":7,\"node_key\":2,\"p\":9}]},\"as\":\"n\"},{\"values\":{\"schema\":{\"part\":{\"type\":\"number\",\"nullable\":false},\"edge_key\":{\"type\":\"number\",\"nullable\":false},\"src_key\":{\"type\":\"number\",\"nullable\":false},\"dst_key\":{\"type\":\"number\",\"nullable\":false},\"w\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"part\":7,\"edge_key\":11,\"src_key\":1,\"dst_key\":2,\"w\":5},{\"part\":7,\"edge_key\":10,\"src_key\":2,\"dst_key\":2,\"w\":2}]},\"as\":\"e\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"n\",\"key\":[\"part\",\"node_key\"],\"labels\":[{\"name\":\"Person\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"p\",\"to\":\"p\"}]}}]}],\"edges\":[{\"name\":\"E\",\"from\":\"e\",\"key\":[\"part\",\"edge_key\"],\"source\":{\"definition\":\"N\",\"key\":[\"part\",\"src_key\"]},\"target\":{\"definition\":\"N\",\"key\":[\"part\",\"dst_key\"]},\"labels\":[{\"name\":\"R\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"w\",\"to\":\"w\"}]}}]}]},\"as\":\"g\"},{\"from\":\"g\",\"node_rows\":true,\"as\":\"identities\"},{\"from\":\"identities\",\"filter\":{\"eq\":[{\"field\":\"node_key\"},{\"literal\":1}]}},{\"select\":[\"id\"],\"as\":\"selected\"},{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":\"selected\",\"id\":\"id\"}},\"as\":\"peer\"},{\"from\":\"g\",\"subtract_graphs\":{\"with\":\"peer\"},\"as\":\"combined\"},{\"from\":\"combined\",\"node_rows\":true,\"as\":\"nodes\"},{\"from\":\"nodes\",\"select\":[\"p\",\"part\",\"node_key\",\"labels\"],\"as\":\"node_projection\"},{\"from\":\"combined\",\"edge_rows\":true},{\"select\":[\"w\",\"part\",\"edge_key\",\"labels\"]},{\"sort\":[{\"field\":\"edge_key\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"edge_projection\"}],\"results\":{\"nodes\":{\"from\":\"node_projection\",\"fields\":[\"p\",\"part\",\"node_key\",\"labels\"]},\"edges\":{\"from\":\"edge_projection\",\"fields\":[\"w\",\"part\",\"edge_key\",\"labels\"]}}}],\"results\":{\"nodes\":{\"from\":{\"stage\":\"main\",\"result\":\"nodes\"}},\"edges\":{\"from\":{\"stage\":\"main\",\"result\":\"edges\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_graph_union_source(control)
}

///|
test "complete public subtraction sources retain empty NULL and nonempty endpoint contracts" {
  check_graph_union_source(
    compile_data_set(
      "DATA n = SELECT 7 AS part, 1 AS node_key, 7 AS p UNION ALL SELECT 7 AS part, 2 AS node_key, 9 AS p; DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 2 AS dst_key, 5 AS w UNION ALL SELECT 7 AS part, 10 AS edge_key, 2 AS src_key, 2 AS dst_key, 2 AS w; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); DATA selected = FROM g |> node_rows() |> WHERE node_key = 1 |> SELECT id; DATA peer = FROM g |> subgraph(nodes: {from: selected, id: \"id\"}); FROM g |> subtract_graphs(with: peer) |> edge_rows() |> SELECT w, part, edge_key, labels |> ORDER BY edge_key |> RESULT edges",
    ),
  )
  check_graph_union_source(
    compile_data_set(
      "DATA n = SELECT 7 AS part, 1 AS node_key, CAST(NULL AS FLOAT64) AS p; DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); FROM g |> subtract_graphs(with: g) |> node_rows() |> SELECT p, part, node_key, labels |> ORDER BY node_key |> RESULT nodes",
    ),
  )
  check_graph_union_source(
    compile_data_set(
      "DATA n = SELECT 7 AS part, 1 AS node_key, 0 AS p; DATA e = SELECT 7 AS part, 11 AS edge_key, 1 AS src_key, 1 AS dst_key, 5 AS w UNION ALL SELECT 7 AS part, 10 AS edge_key, 1 AS src_key, 1 AS dst_key, 2 AS w; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, node_key) LABEL Person PROPERTIES (p)) EDGE TABLES (e AS E KEY (part, edge_key) SOURCE KEY (part, src_key) REFERENCES N DESTINATION KEY (part, dst_key) REFERENCES N LABEL R PROPERTIES (w))); FROM g |> subtract_graphs(with: g, merge: {node_properties: {p: 'number_sum'}}) |> node_rows() |> SELECT p, part, node_key, labels |> ORDER BY node_key |> RESULT nodes",
    ),
  )
}
