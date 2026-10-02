///|
test "unsupported Graph bounds cannot expose invented nullable identity diagnostic rows" {
  let issue = @pipeline_typing.check_carriers(
    cursor(
      "[{\"graph_bounds\":{\"max_degree\":0},\"as\":\"violations\"},{\"select\":[\"kind\",\"node_id\",\"actual\",\"max\"]}]",
    ),
    [("g", graph_input())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
  assert_eq(issue.path, [Index(0), Key("graph_bounds")])
}
