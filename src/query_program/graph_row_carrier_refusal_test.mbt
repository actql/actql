///|
test "Graph row continuation rejects restoring a consumed Graph Carrier" {
  for
    tail in [
      "FROM g |> node_rows() |> union_graphs(with: g)", "FROM g |> node_rows() |> subtract_graphs(with: g)",
      "FROM g |> node_rows() |> subgraph(nodes: {ids: []}) |> SELECT node_key",
    ] {
    let actual = classified_graph_source(graph_rows_prefix() + tail)
    assert_true(actual is Err(InvalidQuery), msg=tail)
  }
}
