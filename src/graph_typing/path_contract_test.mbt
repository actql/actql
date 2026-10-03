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
  // Two array wrappers, five fields, and their independently counted names.
  assert_eq((usage.work, usage.nodes, usage.text_bytes), (7, 2, 39))
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
}

///|
test "current node contract retains typed identities and exact schema budget" {
  let source = cursor("true")
  let graph = current_scope_graph()
  let checked = @graph_typing.check_path_contract(
    TraversedNodes,
    source,
    graph,
    limits(),
  ).unwrap()
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.path_output(checked)).unwrap(),
  ).unwrap()
  for name in ["start_id", "node_id"] {
    let field = @row.lookup(rows, Unqualified(name)).unwrap()
    assert_true(field.shape is @contract.Json)
    assert_false(field.nullable)
  }
  let depth = @row.lookup(rows, Unqualified("depth")).unwrap()
  assert_true(depth.shape is @contract.Number)
  assert_false(depth.nullable)
  let usage = @graph_typing.path_usage(checked)
  assert_eq((usage.work, usage.nodes, usage.text_bytes), (5, 0, 20))
  let exact = { ..limits(), max_work: 5, max_nodes: 0, max_text_bytes: 20, }
  assert_true(
    @graph_typing.check_path_contract(TraversedNodes, source, graph, exact)
    is Ok(_),
  )
  for cap in [{ ..exact, max_work: 4, }, { ..exact, max_text_bytes: 19, }] {
    assert_true(
      @graph_typing.check_path_contract(TraversedNodes, source, graph, cap)
      is Err(_),
    )
  }
}
