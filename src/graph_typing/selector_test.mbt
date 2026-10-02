///|
test "current Graph Relation selectors retain qualified full identity contracts" {
  let graph = current_scope_graph()
  guard graph is @carrier.GraphValue(value) else { fail("Graph") }
  let identity = @carrier.graph_identity(value)
  let relation = @carrier.relation(
    @carrier.rows(
      [(Qualified(Left, "element"), Some(identity))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
  )
  let source = cursor("{\"from\":\"selected\",\"id\":\"left.element\"}")
  let checked = @graph_typing.check_selector(
    source,
    graph,
    Some(relation),
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(
    @graph_typing.selector_form(checked)
    is RelationIds(from="selected", field=Qualified(Left, "element")),
  )
  assert_true(
    @contract.type_equal(
      identity,
      @graph_typing.selector_identity(checked),
      100,
    ),
  )
  let usage = @graph_typing.selector_usage(checked)
  let exact = {
    ..predicate_limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(
    @graph_typing.check_selector(source, graph, Some(relation), None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_selector(source, graph, Some(relation), None, cap)
      is Err(_),
    )
  }
  let numeric = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  )
  assert_true(
    @graph_typing.check_selector(
      cursor("{\"from\":\"r\",\"id\":\"id\"}"),
      graph,
      Some(numeric),
      None,
      predicate_limits(),
    )
    is Err(_),
  )
}

///|
test "current Graph selectors retain repeated typed-domain identity occurrences without tuple fallback" {
  let graph = current_scope_graph()
  let checked = @graph_typing.check_selector(
    cursor(
      "{\"ids\":[" +
      current_node_identity(10) +
      "," +
      current_node_identity(2) +
      "," +
      current_node_identity(10) +
      "]}",
    ),
    graph,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.selector_id_count(checked), 3)
  let detached = @graph_typing.selector_ids(checked)
  for i in 0..<3 {
    assert_true(
      physical_equal(
        detached[i],
        @graph_typing.selector_id_at(checked, i).unwrap(),
      ),
    )
  }
  detached.clear()
  assert_eq(@graph_typing.selector_id_count(checked), 3)
  for i in [-1, 3, 2147483647] {
    assert_true(@graph_typing.selector_id_at(checked, i) is None)
  }
  for
    body in [
      "{}", "{\"ids\":[]}", "{\"ids\":[null]}", "{\"id\":\"element\"}", "{\"from\":\"r\",\"id\":\"element\"}",
      "{\"where\":\"true\"}",
    ] {
    assert_true(
      @graph_typing.check_selector(
        cursor(body),
        graph,
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
}
