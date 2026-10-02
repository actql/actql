///|
test "graph bounds reports retain nullable identity contracts for relation consumers" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"graph_bounds\":{\"max_degree\":0},\"as\":\"violations\"},{\"select\":[\"kind\",\"node_id\",\"actual\",\"max\"]}]",
    ),
    [("g", graph_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let first = @pipeline_typing.step_at(p, 0).unwrap()
  assert_eq(@pipeline_typing.input_occurrences(first)[0].target, Input(0))
  assert_eq(@pipeline_typing.lookup(p, "violations"), Some(Step(0)))
  let schema = @pipeline_typing.output_schema(p).unwrap()
  assert_eq(@schema.field_count(schema), 4)
  let id = @schema.lookup(schema, Unqualified("node_id")).unwrap()
  assert_true(id.nullable)
  assert_true(
    @contract.type_equal(
      id,
      @contract.decimal_contract(38, 9, nullable=true).unwrap(),
      10,
    ),
  )
}
