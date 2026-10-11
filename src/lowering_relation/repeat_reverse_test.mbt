///|
test "repeat ordered arguments and reverse unary body lower to fixed operation tags" {
  for
    (source, expected) in [
      (
        "repeat('😀é',2)", "{\"body\":[{\"body\":\"😀é\",\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"repeat\"}",
      ),
      (
        "reverse('😀é')", "{\"body\":{\"body\":\"😀é\",\"op\":\"literal\"},\"op\":\"reverse\"}",
      ),
    ] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"" + source + "\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(expression_wire(expression), expected)
  }
}

///|
test "repeat reverse ordered reference paths preserve both child positions and prior slots" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ",{\"derive\":[{\"text\":\"chr(id)\"},{\"repeated\":\"repeat(text,id)\"},{\"reversed\":\"reverse(repeated)\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr/body\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body/0\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/1/expr/body/1\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/2/expr/body\",\"target\":{\"prior_slot\":1}}]",
  )
}
