///|
test "current TRAIL admits bounded and patterned forms under shared budgets" {
  let graph = current_scope_graph()
  for
    body in [
      "{\"start\":{\"ids\":[" +
      current_node_identity(2) +
      "]},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3,\"path_mode\":\"trail\",\"emit\":\"paths\",\"edge_types\":[\"Edge\",\"Edge\"],\"max_output_rows\":10}",
      "{\"start\":{\"ids\":[" +
      current_node_identity(2) +
      "]},\"hops\":[{\"direction\":\"in\"},{\"direction\":\"out\",\"edge_types\":[]}],\"path_mode\":\"trail\",\"emit\":\"paths\"}",
    ] {
    let source = cursor(body)
    let checked = @graph_typing.check_traverse(
      source,
      graph,
      None,
      None,
      predicate_limits(),
    ).unwrap()
    assert_eq(@graph_typing.traverse_property_path_mode(checked), Trail)
    let usage = @graph_typing.traverse_usage(checked)
    let exact = {
      ..predicate_limits(),
      max_work: usage.work,
      max_nodes: usage.nodes,
      max_text_bytes: usage.text_bytes,
      max_tokens: usage.tokens,
    }
    assert_true(
      @graph_typing.check_traverse(source, graph, None, None, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: usage.work - 1, },
        { ..exact, max_nodes: usage.nodes - 1, },
        { ..exact, max_text_bytes: usage.text_bytes - 1, },
      ] {
      assert_true(
        @graph_typing.check_traverse(source, graph, None, None, cap) is Err(_),
      )
    }
    assert_true(
      @graph_typing.traverse_pending(checked).contains(EnumeratePropertyPaths),
    )
    if @graph_typing.traverse_patterned(checked) {
      assert_eq(@graph_typing.traverse_bounds(checked), (2.0, 2.0))
      assert_eq(@graph_typing.traverse_hop_count(checked), 2)
    } else {
      assert_eq(@graph_typing.traverse_bounds(checked), (0.0, 3.0))
      let hop = @graph_typing.traverse_hop_at(checked, 0).unwrap()
      let copy = @graph_typing.hop_types(hop).unwrap()
      copy.clear()
      assert_eq(@graph_typing.hop_type_count(hop), Some(2))
    }
  }
}

///|
test "current path hop predicates retain typed edge and node roots" {
  let graph = current_scope_graph()
  let identity = current_node_identity(2)
  for key in ["edge_where", "node_where"] {
    let body = "{\"start\":{\"ids\":[" +
      identity +
      "]},\"hops\":[{\"direction\":\"out\",\"" +
      key +
      "\":\"true\"}],\"path_mode\":\"trail\",\"emit\":\"paths\"}"
    let checked = @graph_typing.check_traverse(
      cursor(body),
      graph,
      None,
      None,
      predicate_limits(),
    ).unwrap()
    let hop = @graph_typing.traverse_hop_at(checked, 0).unwrap()
    assert_true(
      if key == "edge_where" {
        @graph_typing.hop_edge_predicate(hop) is Some(_)
      } else {
        @graph_typing.hop_node_predicate(hop) is Some(_)
      },
    )
  }
  let body = "{\"start\":{\"where\":\"true\"},\"hops\":[{\"direction\":\"out\"}],\"path_mode\":\"trail\",\"emit\":\"paths\"}"
  assert_true(
    @graph_typing.check_traverse(
      cursor(body),
      graph,
      None,
      None,
      predicate_limits(),
    )
    is Err(MatchStructure({ kind: UnsupportedGraphOperation, .. })),
  )
}

///|
test "current TRAIL rejects ambiguous modes and unconnected definition-free predicates" {
  let graph = current_scope_graph()
  let start = "{\"start\":{\"ids\":[" + current_node_identity(2) + "]},"
  for
    suffix in [
      "\"hops\":[],\"emit\":\"paths\",\"path_mode\":\"trail\"}", "\"hops\":[{\"direction\":\"in\"}],\"direction\":\"out\",\"emit\":\"paths\",\"path_mode\":\"trail\"}",
      "\"min_hops\":0,\"max_hops\":3,\"emit\":\"paths\",\"path_mode\":\"trail\"}",
      "\"direction\":\"out\",\"min_hops\":4,\"max_hops\":3,\"emit\":\"paths\",\"path_mode\":\"trail\"}",
      "\"hops\":[{\"direction\":\"in\"}],\"emit\":\"nodes\",\"path_mode\":\"trail\"}",
      "\"hops\":[{\"direction\":\"in\"}],\"emit\":\"paths\"}",
    ] {
    assert_true(
      @graph_typing.check_traverse(
        cursor(start + suffix),
        graph,
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
}
