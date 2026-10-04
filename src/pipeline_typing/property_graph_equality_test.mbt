///|
test "current Graph equality retains two ordered input occurrences and checked obligations" {
  let graph = graph_input()
  let checked = check_carriers(
    cursor(
      "[{\"from\":\"left\",\"graphs_equal\":{\"with\":\"right\"},\"as\":\"comparison\"}]",
    ),
    [("left", graph), ("right", graph)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = step_at(checked, 0).unwrap()
  assert_eq(input_occurrence_count(step), 2)
  assert_eq(input_occurrence_at(step, 0).unwrap().role, Left)
  assert_eq(input_occurrence_at(step, 0).unwrap().target, Input(0))
  assert_eq(input_occurrence_at(step, 1).unwrap().role, Right)
  assert_eq(input_occurrence_at(step, 1).unwrap().target, Input(1))
  guard step.operation is GraphEquality(checked=equal, ..) else {
    fail("expected one typed Graph equality occurrence")
  }
  assert_eq(@graph.property_equality_pending_count(equal), 3)
  let obligations = operation_obligation_group_at(step.operation, 0).unwrap()
  assert_eq(operation_obligations_count(obligations), 3)
  assert_true(
    operation_obligations_at(obligations, 0)
    is Some(PropertyEqualityRequirement(@graph.AdmitBothPropertyGraphs)),
  )
}
