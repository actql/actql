///|
test "Graph bounds exposes typed nullable identity diagnostic rows" {
  let checked = @pipeline_typing.check_carriers(
    cursor(
      "[{\"graph_bounds\":{\"max_degree\":0},\"as\":\"violations\"},{\"select\":[\"kind\",\"node_id\",\"actual\",\"max\"]}]",
    ),
    [("g", graph_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.step_at(checked, 0).unwrap().operation is GraphBounds(_),
  )
  assert_true(
    @pipeline_typing.output_carrier(checked) is Some(@carrier.Relation(_)),
  )
}
