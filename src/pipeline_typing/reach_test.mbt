///|
test "Reach admits nullable Relation starts without replacing typed identities" {
  let graph = graph_graph_scope_input()
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("chosen"),
          Some(@contract.primitive(JsonType, nullable=true)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=6,
    ).unwrap(),
  )
  let pipeline = check_carriers(
    cursor(
      "[{\"from\":\"g\",\"reach\":{\"start\":{\"from\":\"selected\",\"id\":\"chosen\"},\"direction\":\"both\",\"max_depth\":3}}]",
    ),
    [("g", graph), ("selected", relation)],
    None,
    None,
    limits(),
  ).unwrap()
  guard step_at(pipeline, 0).unwrap().operation is Traverse(selector~, checked~) else {
    fail("Reach must reuse the checked traversal owner")
  }
  assert_eq(selector, Some(Input(1)))
  assert_eq(@graph.traverse_bounds(checked), (0.0, 3.0))
  assert_eq(@graph.traverse_emission(checked), @graph.TraversedNodes)
  let output = @graph.traverse_output(checked)
  guard @carrier.relation_rows(output) is Some(rows) else {
    fail("Reach must emit a Relation")
  }
  assert_eq(@carrier.field_count(rows), 3)
  for name in ["start_id", "node_id", "depth"] {
    assert_true(@carrier.lookup(rows, Unqualified(name)) is Present(_))
  }
}

///|
test "Reach selector predicates use common typed expression slots" {
  let pipeline = check_carriers(
    cursor(
      "[{\"from\":\"g\",\"reach\":{\"start\":{\"where\":\"true\"},\"direction\":\"out\",\"max_depth\":1}}]",
    ),
    [("g", graph_graph_scope_input())],
    None,
    None,
    limits(),
  ).unwrap()
  guard step_at(pipeline, 0).unwrap().operation is Traverse(checked~, ..) else {
    fail("Reach must reuse traversal")
  }
  let selector = @graph.traverse_start(checked)
  assert_true(@graph.selector_form(selector) is @graph.NodeWhere)
  assert_true(@graph.selector_predicate(selector) is Some(_))
  let slots = collect_expression_slots(pipeline, max_work=4, max_slots=1).unwrap()
  assert_eq(expression_slot_count(slots), 1)
  assert_eq(
    expression_slot_at(slots, 0).unwrap().consumer,
    GraphNodeSelectorPredicate,
  )
  assert_true(
    collect_expression_slots(pipeline, max_work=3, max_slots=1)
    is Err(WorkLimit),
  )
}
