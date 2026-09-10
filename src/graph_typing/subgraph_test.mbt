///|
test "subgraph shares selector and edge predicate budgets without weakening contracts" {
  let g = match_graph()
  let source = cursor("{\"nodes\":{\"where\":\"active\"},\"edges\":\"active\"}")
  let c = @graph_typing.check_subgraph(
    source,
    g,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(@graph_typing.subgraph_output(c) is GraphValue(_))
  assert_true(@graph_typing.subgraph_edges(c) is Some(_))
  assert_true(
    @graph_typing.subgraph_pending(c).contains(InduceSelectedEndpoints),
  )
  let u = @graph_typing.subgraph_usage(c)
  let exact = {
    ..predicate_limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @graph_typing.check_subgraph(source, g, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_tokens: u.tokens - 1, },
    ] {
    assert_true(
      @graph_typing.check_subgraph(source, g, None, None, cap) is Err(_),
    )
  }
  let c = @graph_typing.check_subgraph(
    cursor("{\"nodes\":{\"ids\":[2]}}"),
    g,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(@graph_typing.subgraph_edges(c) is None)
  assert_true(!@graph_typing.subgraph_pending(c).contains(FilterInducedEdges))
  assert_true(
    @graph_typing.check_subgraph(
      cursor("{\"nodes\":{\"ids\":[2]},\"edges\":{\"literal\":1}}"),
      g,
      None,
      None,
      predicate_limits(),
    )
    is Err(_),
  )
}
