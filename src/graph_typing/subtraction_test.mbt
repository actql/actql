///|
test "subtraction keeps closed binary operand form and shared named property alignment" {
  let number = @contract.primitive(NumberType, nullable=true)
  let left = union_test_graph([
    union_test_node("N", [("p", number), ("q", number)]),
  ])
  let right = union_test_graph([
    union_test_node("N", [("Q", number), ("p", number)]),
  ])
  let checked = @graph_typing.check_subtraction(
    cursor(
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"p\":\"number_sum\"}}}",
    ),
    left,
    right,
    limits(),
  ).unwrap()
  let composition = @graph_typing.subtraction_composition(checked)
  assert_eq(@graph_typing.union_input_count(composition), 2)
  assert_eq(
    @graph_typing.union_field_at(composition, 0, 0, 0, edge=false),
    Some((0, 1, UnionNumberSum)),
  )
  assert_eq(
    @graph_typing.union_field_at(composition, 0, 0, 1, edge=false),
    Some((1, 0, UnionExactEqual)),
  )
  assert_true(
    @graph_typing.subtraction_output(checked) is @carrier.GraphValue(_),
  )
  assert_true(@graph_typing.subtraction_usage(checked).work > 0)
  for
    body in [
      "{\"with\":[\"peer\"]}", "{\"with\":[]}", "{\"with\":\"peer\",\"extra\":true}",
      "{\"with\":\"peer\",\"merge\":{\"other\":{}}}",
    ] {
    assert_true(
      @graph_typing.check_subtraction(cursor(body), left, right, limits())
      is Err(_),
    )
  }
}

///|
test "subtraction retains typed key identity refusal even for empty compatible value domains" {
  let left = union_test_graph([union_test_node("N", [])])
  let right = union_test_graph([union_test_node("n", [])])
  assert_true(
    @graph_typing.check_subtraction(
      cursor("{\"with\":\"peer\"}"),
      left,
      right,
      limits(),
    )
    is Err({ kind: UnionDefinitionIdentityMismatch("N"), .. }),
  )
}
