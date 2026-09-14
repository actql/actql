///|
test "traversal checks homogeneous and patterned forms under shared budgets" {
  let g = match_graph()
  for
    text in [
      "{\"start\":{\"ids\":[2]},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3,\"emit\":\"paths\",\"edge_types\":[\"owns\",\"owns\"],\"max_output_rows\":10}",
      "{\"start\":{\"where\":\"active\"},\"hops\":[{\"direction\":\"in\",\"edge_where\":\"active\",\"node_where\":\"active\"},{\"direction\":\"out\",\"edge_types\":[]}],\"emit\":\"nodes\"}",
    ] {
    let source = cursor(text)
    let c = @graph_typing.check_traverse(
      source,
      g,
      None,
      None,
      predicate_limits(),
    ).unwrap()
    let u = @graph_typing.traverse_usage(c)
    let exact = {
      ..predicate_limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
      max_tokens: u.tokens,
    }
    assert_true(
      @graph_typing.check_traverse(source, g, None, None, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @graph_typing.check_traverse(source, g, None, None, cap) is Err(_),
      )
    }
    if @graph_typing.traverse_patterned(c) {
      assert_eq(@graph_typing.traverse_bounds(c), (2.0, 2.0))
      assert_eq(@graph_typing.traverse_hop_count(c), 2)
      assert_true(
        @graph_typing.check_traverse(source, g, None, None, {
          ..exact,
          max_tokens: u.tokens - 1,
        })
        is Err(_),
      )
    } else {
      assert_eq(@graph_typing.traverse_bounds(c), (0.0, 3.0))
      let hop = @graph_typing.traverse_hop_at(c, 0).unwrap()
      assert_eq(@graph_typing.hop_types(hop), Some(["owns", "owns"]))
      assert_eq(@graph_typing.hop_type_count(hop), Some(2))
      let copy = @graph_typing.hop_types(hop).unwrap()
      copy.clear()
      assert_eq(@graph_typing.hop_type_count(hop), Some(2))
      assert_eq(@graph_typing.hop_types(hop).unwrap().length(), 2)
      assert_true(
        indexed_obligation_copy(
          @graph_typing.traverse_pending(c),
          @graph_typing.traverse_pending_count(c),
          i => @graph_typing.traverse_pending_at(c, i),
          (a, b) => a == b,
        ).contains(EnumerateSimplePaths),
      )
    }
  }
}

///|
test "traversal rejects mixed modes missing directions and undeclared edge labels" {
  for
    text in [
      "{\"start\":{\"ids\":[2]},\"hops\":[],\"emit\":\"nodes\"}", "{\"start\":{\"ids\":[2]},\"hops\":[{\"direction\":\"in\"}],\"direction\":\"out\",\"emit\":\"nodes\"}",
      "{\"start\":{\"ids\":[2]},\"min_hops\":0,\"max_hops\":3,\"emit\":\"nodes\"}",
      "{\"start\":{\"ids\":[2]},\"direction\":\"out\",\"min_hops\":4,\"max_hops\":3,\"emit\":\"nodes\"}",
      "{\"start\":{\"ids\":[2]},\"hops\":[{\"direction\":\"in\",\"node_where\":{\"literal\":1}}],\"emit\":\"nodes\"}",
      "{\"start\":{\"ids\":[2]},\"hops\":[{\"direction\":\"in\"}],\"emit\":\"nodes\",\"max_paths\":10}",
    ] {
    assert_true(
      @graph_typing.check_traverse(
        cursor(text),
        match_graph(),
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
  let g = complete_graph(
    @contract.primitive(NumberType, nullable=false),
    @contract.primitive(BooleanType, nullable=false),
    "owns",
  )
  let e = @graph_typing.check_traverse(
    cursor(
      "{\"start\":{\"ids\":[2]},\"hops\":[{\"direction\":\"in\",\"edge_types\":[]}],\"emit\":\"nodes\"}",
    ),
    g,
    None,
    None,
    predicate_limits(),
  )
  assert_true(e is Err(MatchStructure({ kind: MissingEdgeLabel, .. })))
}
