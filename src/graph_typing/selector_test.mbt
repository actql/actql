///|
test "graph selectors preserve Ref identity contracts from qualified Relation columns" {
  let reference = @contract.read_checked(
    cursor(
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let g = complete_graph(
    reference,
    @contract.primitive(BooleanType, nullable=false),
    "a",
  )
  let rows = @carrier.rows(
    [(Qualified(Left, "id"), Some(reference)), (Unqualified("unrelated"), None)],
    field_set=Open,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let relation = @carrier.relation(rows)
  let source = cursor("{\"from\":\"selected\",\"id\":\"left.id\"}")
  let c = @graph_typing.check_selector(
    source,
    g,
    Some(relation),
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(
    @graph_typing.selector_form(c)
    is RelationIds(from="selected", field=Qualified(Left, "id")),
  )
  assert_true(
    @contract.type_equal(reference, @graph_typing.selector_identity(c), 100),
  )
  assert_true(
    @graph_typing.selector_pending(c).contains(RevalidateSelectorReferences),
  )
  assert_true(
    @graph_typing.selector_pending(c).contains(RequireSelectorMembership),
  )
  let u = @graph_typing.selector_usage(c)
  let exact = {
    ..predicate_limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @graph_typing.check_selector(source, g, Some(relation), None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_selector(source, g, Some(relation), None, cap)
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
      g,
      Some(numeric),
      None,
      predicate_limits(),
    )
    is Err(_),
  )
}

///|
test "graph selectors keep literal occurrences and admit predicate empty selection" {
  let g = match_graph()
  let ids = @graph_typing.check_selector(
    cursor("{\"ids\":[10,2,10]}"),
    g,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.selector_ids(ids).length(), 3)
  let copy = @graph_typing.selector_ids(ids)
  copy.clear()
  assert_eq(@graph_typing.selector_ids(ids).length(), 3)
  let p = @graph_typing.check_selector(
    cursor("{\"where\":{\"literal\":false}}"),
    g,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(@graph_typing.selector_predicate(p) is Some(_))
  for
    body in [
      "{}", "{\"ids\":[]}", "{\"ids\":[null]}", "{\"ids\":[2],\"where\":{\"literal\":true}}",
      "{\"id\":\"node_id\"}", "{\"ids\":[2],\"id\":\"node_id\"}", "{\"from\":\"r\",\"id\":\"node_id\"}",
    ] {
    assert_true(
      @graph_typing.check_selector(
        cursor(body),
        g,
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
}
