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
test "retired node emission is refused before any checked path grant" {
  let source = cursor(
    "{\"start\":{\"ids\":[{\"domain\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"definition\":\"N\",\"key\":[1,\"one\"],\"key_types\":[{\"kind\":\"number\"},{\"kind\":\"string\"}]}]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":1,\"path_mode\":\"trail\",\"emit\":\"nodes\"}",
  )
  let issue = @graph_typing.check_traverse(
    source,
    current_scope_graph(),
    None,
    None,
    predicate_limits(),
  ).unwrap_err()
  assert_eq(
    @graph_typing.match_diagnostic(issue, source).kind,
    Structure(UnsupportedGraphProfile),
  )
}
