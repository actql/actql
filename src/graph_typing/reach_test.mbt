///|
test "reach checks typed start and explicit direction with bounded traversal obligations" {
  let g = match_graph()
  let source = cursor("{\"start\":2,\"direction\":\"both\",\"max_depth\":3}")
  let c = @graph_typing.check_reach(source, g, limits()).unwrap()
  assert_eq(@graph_typing.reach_direction(c), Both)
  assert_eq(@graph_typing.reach_max_depth(c), 3.0)
  assert_true(
    indexed_obligation_copy(
      @graph_typing.reach_pending(c),
      @graph_typing.reach_pending_count(c),
      i => @graph_typing.reach_pending_at(c, i),
      (a, b) => a == b,
    ).contains(RequireReachStartMembership),
  )
  let rows = @carrier.relation_rows(@graph_typing.reach_output(c)).unwrap()
  assert_eq(@carrier.field_count(rows), 3)
  assert_true(
    @carrier.lookup(rows, Unqualified("node_id"))
    is Present({ contract: Some({ shape: @contract.Number, .. }), .. }),
  )
  let u = @graph_typing.reach_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@graph_typing.check_reach(source, g, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(@graph_typing.check_reach(source, g, cap) is Err(_))
  }
  for
    source in [
      "{\"start\":2,\"max_depth\":3}", "{\"start\":\"2\",\"direction\":\"in\",\"max_depth\":3}",
      "{\"start\":2,\"direction\":\"out\",\"max_depth\":0}", "{\"start\":2,\"direction\":\"both\",\"max_depth\":1.5}",
      "{\"start\":2,\"direction\":\"both\",\"max_depth\":3,\"max_paths\":2}",
    ] {
    assert_true(
      @graph_typing.check_reach(cursor(source), g, limits()) is Err(_),
    )
  }
}

///|
test "reach rejects semantic alias collisions and retains large integer depth" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let id = @contract.primitive(NumberType, nullable=false)
  let names = @carrier.graph_row_names(
    Unqualified("depth"),
    Unqualified("source"),
    Unqualified("target"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let g = @carrier.graph(
    id,
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  assert_true(
    @graph_typing.check_reach(
      cursor("{\"start\":2,\"direction\":\"in\",\"max_depth\":1}"),
      g,
      limits(),
    )
    is Err(MatchStructure({ kind: ScopeCollision("depth"), .. })),
  )
  let c = @graph_typing.check_reach(
    cursor(
      "{\"start\":2,\"direction\":\"both\",\"max_depth\":9007199254740992}",
    ),
    match_graph(),
    limits(),
  ).unwrap()
  assert_eq(@graph_typing.reach_max_depth(c), 9007199254740992.0)
}

///|
test "Reach admits the common selector without weakening typed starts" {
  let graph = match_graph()
  let body = fn(start : String) {
    cursor("{\"start\":" + start + ",\"direction\":\"out\",\"max_depth\":2}")
  }
  let explicit = @graph_typing.check_reach(
    body("{\"ids\":[2,10,2]}"),
    graph,
    limits(),
  ).unwrap()
  assert_true(
    @graph_typing.reach_start(explicit) is SelectedReachStarts(selector) &&
    @graph_typing.selector_id_count(selector) == 3,
  )
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("key"),
          Some(@contract.primitive(NumberType, nullable=true)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=16,
    ).unwrap(),
  )
  assert_true(
    @graph_typing.check_reach(
      body("{\"from\":\"seeds\",\"id\":\"key\"}"),
      graph,
      limits(),
      selector_relation=Some(relation),
    )
    is Ok(_),
  )
  assert_true(
    @graph_typing.check_reach(
      body("{\"from\":\"seeds\",\"id\":\"key\"}"),
      graph,
      limits(),
    )
    is Err(_),
  )
  let wrong = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("key"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=16,
    ).unwrap(),
  )
  assert_true(
    @graph_typing.check_reach(
      body("{\"from\":\"seeds\",\"id\":\"key\"}"),
      graph,
      limits(),
      selector_relation=Some(wrong),
    )
    is Err(_),
  )
  assert_true(
    @graph_typing.check_reach(
      body("{\"where\":{\"literal\":false}}"),
      graph,
      limits(),
      max_tokens=100,
    )
    is Ok(_),
  )
  for invalid in ["{\"ids\":[]}", "{\"ids\":[\"2\"]}"] {
    assert_true(
      @graph_typing.check_reach(body(invalid), graph, limits()) is Err(_),
    )
  }
}
