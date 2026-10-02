///|
test "current path contracts retain full independent edge identities and reject tuple-path schemas" {
  let graph = current_scope_graph()
  let source = cursor("true")
  let checked = @graph_typing.check_path_contract(
    TraversedPaths,
    source,
    graph,
    limits(),
  ).unwrap()
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.path_output(checked)).unwrap(),
  ).unwrap()
  for name in ["node_ids", "edge_ids"] {
    guard @row.lookup(rows, Unqualified(name)).unwrap().shape
      is @contract.Array(element, ..) else {
      fail("identity array")
    }
    assert_true(element.shape is @contract.Json)
    assert_false(element.nullable)
  }
  let usage = @graph_typing.path_usage(checked)
  let exact = {
    ..limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(
    @graph_typing.check_path_contract(TraversedPaths, source, graph, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
      { ..exact, max_depth: 1, },
    ] {
    assert_true(
      @graph_typing.check_path_contract(TraversedPaths, source, graph, cap)
      is Err(_),
    )
  }
  for kind in [@graph_typing.TraversedNodes, @graph_typing.ShortestPaths] {
    assert_true(
      @graph_typing.check_path_contract(kind, source, graph, limits())
      is Err({ kind: UnsupportedGraphOperation, .. }),
    )
  }
  assert_true(
    @graph_typing.check_path_contract(
      TraversedPaths,
      source,
      graph,
      limits(),
      property_paths=false,
    )
    is Err({ kind: UnsupportedGraphOperation, .. }),
  )
}
