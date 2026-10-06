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
  assert_eq(@graph_typing.match_definition_index(checked), 0)
  assert_eq(@graph_typing.match_graph_element_definition_name(checked), "N")
  assert_eq(
    @carrier.field_count(@graph_typing.match_property_schema(checked)),
    0,
  )
  assert_eq(
    @carrier.field_count(@graph_typing.match_graph_scope_fields(checked)),
    1,
  )
  assert_eq(
    @graph_typing.match_graph_binding(checked, "identity"),
    Some(@row.Unqualified("element")),
  )
  assert_true(
    @graph_typing.match_pending(checked).contains(
      @graph_typing.ResolveGraphMatchProfile,
    ),
  )
  let pending = @graph_typing.match_pending(checked)
  assert_eq(pending, [
    @graph_typing.AdmitMatchGraphData,
    @graph_typing.CanonicalMatchOrder,
    @graph_typing.ResolveMatchResources,
    @graph_typing.ResolveGraphMatchProfile,
    @graph_typing.EvaluateMatchPredicate,
  ])
  assert_eq(@graph_typing.match_pending_count(checked), pending.length())
  for index in 0..<pending.length() {
    assert_eq(
      @graph_typing.match_pending_at(checked, index),
      Some(pending[index]),
    )
  }
  assert_eq(@graph_typing.match_pending_at(checked, -1), None)
  assert_eq(@graph_typing.match_pending_at(checked, pending.length()), None)
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
