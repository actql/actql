///|
fn match_graph() -> @carrier.Carrier {
  let boolean = @contract.primitive(BooleanType, nullable=true)
  let props = @carrier.rows(
    [(Unqualified("active"), Some(boolean))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node_id"),
    Unqualified("source_id"),
    Unqualified("target_id"),
    Some(Unqualified("edge_type")),
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    props,
    props,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
    label_contract=Some(@contract.primitive(StringType, nullable=true)),
  ).unwrap()
}

///|
test "graph matches retain typed repeated IDs and project declared fields" {
  let body = cursor("{\"ids\":[2,10,2],\"fields\":[\"node_id\",\"active\"]}")
  let c = @graph_typing.check_match(
    Nodes,
    body,
    match_graph(),
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.match_ids(c).length(), 3)
  assert_true(
    indexed_obligation_copy(
      @graph_typing.match_pending(c),
      @graph_typing.match_pending_count(c),
      i => @graph_typing.match_pending_at(c, i),
      (a, b) => a == b,
    ).contains(ValidateSelectedIdentityMembership),
  )
  let ids = @graph_typing.match_ids(c)
  ids.clear()
  assert_eq(@graph_typing.match_ids(c).length(), 3)
  let u = @graph_typing.match_usage(c)
  let exact = {
    ..predicate_limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @graph_typing.check_match(Nodes, body, match_graph(), None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_match(Nodes, body, match_graph(), None, cap) is Err(_),
    )
  }
  for
    body in [
      "{\"ids\":[],\"fields\":[\"node_id\"]}", "{\"ids\":[\"2\"],\"fields\":[\"node_id\"]}",
      "{\"ids\":[null],\"fields\":[\"node_id\"]}", "{\"where\":{\"literal\":true},\"fields\":[\"id\"]}",
      "{\"where\":{\"literal\":true},\"fields\":[\"active\",\"active\"]}", "{\"where\":{\"literal\":true},\"ids\":[2],\"fields\":[\"active\"]}",
    ] {
    assert_true(
      @graph_typing.check_match(
        Nodes,
        cursor(body),
        match_graph(),
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "edge matching retains empty and repeated type filters and typed predicates" {
  for types in ["[]", "[\"owns\",\"owns\"]"] {
    let source = cursor(
      "{\"types\":" +
      types +
      ",\"where\":\"active\",\"fields\":[\"source_id\",\"edge_type\"]}",
    )
    let c = @graph_typing.check_match(
      Edges,
      source,
      match_graph(),
      None,
      predicate_limits(),
    ).unwrap()
    assert_true(@graph_typing.match_predicate(c) is Some(_))
    assert_true(@graph_typing.match_types(c) is Some(_))
    assert_true(
      indexed_obligation_copy(
        @graph_typing.match_pending(c),
        @graph_typing.match_pending_count(c),
        i => @graph_typing.match_pending_at(c, i),
        (a, b) => a == b,
      ).contains(FilterSelectedEdgeTypes),
    )
    let rows = @carrier.relation_rows(@graph_typing.match_output(c)).unwrap()
    assert_eq(@carrier.field_count(rows), 2)
  }
}
