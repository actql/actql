///|
test "subtraction retains two ordered borrowed occurrences and its own endpoint closure obligation" {
  let graph = graph_input()
  let checked = check_carriers(
    cursor(
      "[{\"from\":\"g\",\"subtract_graphs\":{\"with\":\"g\"},\"as\":\"remaining\"}]",
    ),
    [("g", graph)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = step_at(checked, 0).unwrap()
  assert_eq(input_occurrence_count(step), 2)
  assert_eq(input_occurrence_at(step, 0).unwrap().target, Input(0))
  assert_eq(input_occurrence_at(step, 1).unwrap().target, Input(0))
  assert_eq(input_occurrence_at(step, 0).unwrap().role, Left)
  assert_eq(input_occurrence_at(step, 1).unwrap().role, Right)
  guard step.operation is GraphSubtraction(right=Input(0), ..) else {
    fail("checked subtraction expected")
  }
  let obligations = operation_obligation_group_at(step.operation, 0).unwrap()
  assert_eq(operation_obligations_count(obligations), 7)
  assert_true(
    operation_obligations_at(obligations, 4)
    is Some(SubtractionRequirement(@graph.InduceSubtractionEndpoints)),
  )
  assert_true(operation_obligations_graph_subtraction(obligations) is Some(_))
  assert_true(operation_obligations_graph_union(obligations) is None)
  for body in ["{\"with\":[\"g\"]}", "{\"with\":\"g\",\"extra\":0}"] {
    assert_true(
      check_carriers(
        cursor("[{\"from\":\"g\",\"subtract_graphs\":" + body + "}]"),
        [("g", graph)],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
