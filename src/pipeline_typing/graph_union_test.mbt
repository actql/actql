///|
test "union retains repeated authored Graph occurrences and common obligations" {
  let graph = graph_input()
  let checked = check_carriers(
    cursor(
      "[{\"from\":\"left\",\"union_graphs\":{\"with\":[\"right\",\"left\",\"right\"]},\"as\":\"combined\"}]",
    ),
    [("left", graph), ("right", graph)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = step_at(checked, 0).unwrap()
  assert_eq(input_occurrence_count(step), 4)
  let expected : Array[(Int, Target)] = [
    (0, Input(0)),
    (1, Input(1)),
    (2, Input(0)),
    (3, Input(1)),
  ]
  for (index, target) in expected {
    assert_eq(input_occurrence_at(step, index).unwrap().target, target)
    assert_eq(
      input_occurrence_at(step, index).unwrap().role,
      if index == 0 {
        Primary
      } else {
        Sample(index)
      },
    )
  }
  guard step.operation is GraphUnion(checked=operation, ..) else {
    fail("checked union expected")
  }
  assert_eq(@graph.union_input_count(operation), 4)
  let obligations = operation_obligation_group_at(step.operation, 0).unwrap()
  assert_eq(operation_obligations_count(obligations), 6)
  assert_true(
    operation_obligations_at(obligations, 2)
    is Some(UnionRequirement(@graph.CheckUnionEdgeEndpoints)),
  )
  assert_true(operation_obligations_graph_union(obligations) is Some(_))
}
