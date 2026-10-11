///|
test "Graph graft public AQL retains its own binary operation and Graph row consumer" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","graft_graph":{"with":"aql_with_graph_2"},"as":"aql_sga_3"},{"from":"aql_sga_3","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_graph_union_source(expected)
  let actual = compile_data_set(
    graph_union_prefix() +
    "FROM g |> graft_graph(with: g) |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(expected))
  check_graph_union_source(actual)
  let bound = compile_data_set(
    graph_union_prefix() +
    ", h AS (FROM g |> graft_graph(with: g)) FROM h |> node_rows() |> SELECT p, node_key",
  )
  check_graph_union_source(bound)
}

///|
test "Graph graft source does not admit union lists merge policies or Relation peers" {
  for
    suffix in [
      "FROM g |> graft_graph(with: [g]) |> node_rows()", "FROM g |> graft_graph(with: g, merge: {}) |> node_rows()",
      "FROM g |> graft_graph(with: n) |> node_rows()", "FROM g |> graft_graph(with: missing) |> node_rows()",
    ] {
    assert_true(
      classified_graph_source(graph_union_prefix() + suffix) is Err(_),
      msg=suffix,
    )
  }
}

///|
test "Graph graft malformed binary arguments are input violations not support gaps" {
  for
    suffix in [
      "FROM g |> graft_graph(with: [g]) |> node_rows()", "FROM g |> graft_graph(with: g, merge: {}) |> node_rows()",
    ] {
    assert_true(
      classified_graph_source(graph_union_prefix() + suffix)
      is Err(InvalidQuery),
      msg=suffix,
    )
  }
}
