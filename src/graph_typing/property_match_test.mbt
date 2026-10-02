///|
test "keyed match scopes retain definition typing and never reinterpret the legacy profile" {
  let graph = keyed_profile()
  let body = cursor(
    "{\"definition\":\"N\",\"label\":\"node\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}",
  )
  let checked = @graph_typing.check_match(
    @graph_typing.Nodes,
    body,
    graph,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.match_property_definition(checked), Some(0))
  assert_eq(
    @graph_typing.match_property_binding(checked, "identity"),
    Some(@row.Unqualified("element")),
  )
  assert_true(
    @graph_typing.match_pending(checked).contains(
      @graph_typing.ResolvePropertyGraphMatchProfile,
    ),
  )
  assert_false(
    @graph_typing.match_pending(checked).contains(
      @graph_typing.ResolveMatchProfile,
    ),
  )
  assert_true(
    @graph_typing.check_match(
      @graph_typing.Nodes,
      body,
      @carrier.unknown_carrier(GraphKind),
      None,
      predicate_limits(),
    )
    is Err(_),
  )
  for
    invalid in [
      "{\"where\":\"true\",\"fields\":[\"element\"]}", "{\"definition\":\"unknown\",\"where\":\"true\",\"fields\":[\"element\"]}",
      "{\"definition\":\"N\",\"label\":\"unknown\",\"where\":\"true\",\"fields\":[\"element\"]}",
      "{\"definition\":\"N\",\"bindings\":{\"source\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}",
    ] {
    assert_true(
      @graph_typing.check_match(
        @graph_typing.Nodes,
        cursor(invalid),
        graph,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
  let usage = @graph_typing.match_usage(checked)
  let exact = {
    ..predicate_limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_tokens: usage.tokens,
  }
  assert_true(
    @graph_typing.check_match(@graph_typing.Nodes, body, graph, None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_match(@graph_typing.Nodes, body, graph, None, cap)
      is Err(_),
    )
  }
}
