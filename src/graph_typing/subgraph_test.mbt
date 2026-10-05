///|
test "subgraph retains full Graph identity and charges selector and edge predicate together" {
  let graph = current_scope_graph()
  let source = cursor(
    "{\"nodes\":{\"ids\":[" +
    current_node_identity(2) +
    "]},\"edges\":\"title = 'kept'\"}",
  )
  let checked = @graph_typing.check_subgraph(
    source,
    graph,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(@graph_typing.subgraph_output(checked) is @carrier.GraphValue(_))
  assert_eq(
    @graph_typing.selector_id_count(@graph_typing.subgraph_nodes(checked)),
    1,
  )
  assert_true(@graph_typing.subgraph_edges(checked) is Some(_))
  assert_true(
    @graph_typing.subgraph_pending(checked).contains(FilterInducedEdges),
  )
  assert_true(
    @carrier.lookup(
      @graph_typing.subgraph_edge_fields(checked),
      Unqualified("title"),
    )
    is Present(_),
  )
  assert_eq(
    @graph_typing.subgraph_edge_property_position(checked, 0, 0),
    Some(0),
  )
  let usage = @graph_typing.subgraph_usage(checked)
  let exact = {
    ..predicate_limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_tokens: usage.tokens,
  }
  assert_true(
    @graph_typing.check_subgraph(source, graph, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
      { ..exact, max_tokens: usage.tokens - 1, },
    ] {
    assert_true(
      @graph_typing.check_subgraph(source, graph, None, None, cap) is Err(_),
    )
  }
}

///|
test "subgraph keeps Relation identity selection and static edge property scope" {
  let graph = heterogeneous_traversal_graph()
  guard graph is @carrier.GraphValue(value) else { fail("Graph") }
  let identity = @carrier.graph_identity(value)
  let relation = @carrier.relation(
    @carrier.rows(
      [(Unqualified("element"), Some(identity))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
  )
  let accepted = cursor(
    "{\"nodes\":{\"from\":\"selected\",\"id\":\"element\"},\"edges\":\"shared > 0\"}",
  )
  let checked = @graph_typing.check_subgraph(
    accepted,
    graph,
    Some(relation),
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(
    @graph_typing.selector_form(@graph_typing.subgraph_nodes(checked))
    is RelationIds(from="selected", field=Unqualified("element")),
  )
  assert_eq(
    @graph_typing.subgraph_edge_property_position(checked, 0, 0),
    Some(0),
  )
  assert_eq(
    @graph_typing.subgraph_edge_property_position(checked, 1, 0),
    Some(0),
  )
  assert_true(
    @graph_typing.check_subgraph(
      cursor(
        "{\"nodes\":{\"from\":\"selected\",\"id\":\"element\"},\"edges\":\"weight > 0\"}",
      ),
      graph,
      Some(relation),
      None,
      predicate_limits(),
    )
    is Err(@graph_typing.MatchPredicate(UnknownPredicateField(_))),
  )
}
