///|
fn weighted_graph(nullable : Bool) -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let edges = @carrier.rows(
    [(Unqualified("cost"), Some(@contract.primitive(NumberType, nullable~)))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  @carrier.graph(
    number,
    empty,
    edges,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
test "shortest paths keep typed endpoints and defer all-edge weight validation" {
  let source = cursor(
    "{\"source\":2,\"target\":2,\"direction\":\"both\",\"max_hops\":3,\"weight\":\"cost\",\"max_output_rows\":10}",
  )
  let g = weighted_graph(false)
  let c = @graph_typing.check_shortest(
    source,
    g,
    None,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.shortest_selection(c), EachPair)
  assert_true(@graph_typing.shortest_endpoint(c, Left) is Single(_))
  assert_eq(@graph_typing.shortest_weight(c), Some(Unqualified("cost")))
  assert_true(
    indexed_obligation_copy(
      @graph_typing.shortest_pending(c),
      @graph_typing.shortest_pending_count(c),
      i => @graph_typing.shortest_pending_at(c, i),
      (a, b) => a == b,
    ).contains(ValidateAllNonnegativeFiniteWeights),
  )
  assert_true(
    indexed_obligation_copy(
      @graph_typing.shortest_pending(c),
      @graph_typing.shortest_pending_count(c),
      i => @graph_typing.shortest_pending_at(c, i),
      (a, b) => a == b,
    ).contains(RejectSelectedOverrangeAtomically),
  )
  let rows = @carrier.relation_rows(@graph_typing.shortest_output(c)).unwrap()
  assert_eq(@carrier.field_count(rows), 6)
  let u = @graph_typing.shortest_usage(c)
  let exact = {
    ..predicate_limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @graph_typing.check_shortest(source, g, None, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_shortest(source, g, None, None, None, cap) is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_shortest(
      source,
      weighted_graph(true),
      None,
      None,
      None,
      predicate_limits(),
    )
    is Err(MatchStructure({ kind: InvalidWeight, .. })),
  )
}

///|
test "set endpoints require selection and share both predicate token budgets" {
  for selection in ["each_pair", "nearest_pair", "nearest_per_source"] {
    let source = cursor(
      "{\"source\":{\"where\":\"active\"},\"target\":{\"where\":\"active\"},\"selection\":\"" +
      selection +
      "\",\"direction\":\"out\",\"max_hops\":1}",
    )
    let c = @graph_typing.check_shortest(
      source,
      match_graph(),
      None,
      None,
      None,
      predicate_limits(),
    ).unwrap()
    assert_true(@graph_typing.shortest_endpoint(c, Right) is Selected(_))
    let u = @graph_typing.shortest_usage(c)
    assert_true(
      @graph_typing.check_shortest(source, match_graph(), None, None, None, {
        ..predicate_limits(),
        max_tokens: u.tokens - 1,
      })
      is Err(_),
    )
  }
  for
    body in [
      "{\"source\":2,\"target\":3,\"direction\":\"in\",\"max_hops\":1,\"selection\":\"each_pair\"}",
      "{\"source\":{\"ids\":[2]},\"target\":3,\"direction\":\"in\",\"max_hops\":1}",
      "{\"source\":2,\"target\":3,\"max_hops\":1}", "{\"source\":2,\"target\":3,\"direction\":\"in\",\"max_hops\":0}",
      "{\"source\":2,\"target\":3,\"direction\":\"in\",\"max_hops\":1,\"max_paths\":2}",
    ] {
    assert_true(
      @graph_typing.check_shortest(
        cursor(body),
        match_graph(),
        None,
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
}
