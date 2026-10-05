///|
test "finished Storage belongs only to its exact live builder generation" {
  guard graph_fixture() is @carrier.GraphValue(graph) else { abort("Graph") }
  let first = prepare(@carrier.graph_carrier(graph), DeclaredNodes, limits()).unwrap()
  let second = prepare(@carrier.graph_carrier(graph), DeclaredNodes, limits()).unwrap()
  assert_true(builder_accepts_output(first, graph, limits()))
  assert_false(
    builder_accepts_output(first, graph, { ..limits(), max_nodes: 9, }),
  )
  guard graph_fixture() is @carrier.GraphValue(foreign) else { abort("Graph") }
  assert_false(builder_accepts_output(first, foreign, limits()))
  // Equal, even empty, payloads do not turn one builder into another's owner.
  let first_storage = finish(first).unwrap()
  let second_storage = finish(second).unwrap()
  assert_true(builder_owns_storage(first, first_storage))
  assert_false(builder_owns_storage(first, second_storage))
  assert_false(builder_accepts_output(first, graph, limits()))
  assert_false(cancel(first))
  assert_true(builder_owns_storage(first, first_storage))
  discard(first_storage)
  assert_false(builder_owns_storage(first, first_storage))
  discard(first_storage)
  assert_false(builder_owns_storage(first, first_storage))
  assert_true(builder_owns_storage(second, second_storage))
  discard(second_storage)
}
