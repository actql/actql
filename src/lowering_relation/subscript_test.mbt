///|
test "subscript machine encoding and references retain receiver-before-index demand" {
  let pipeline = expression_pipeline(
    ",{\"from\":\"seed\",\"derive\":[{\"v\":{\"subscript\":{\"value\":{\"array\":[{\"field\":\"id\"}]},\"index\":{\"field\":\"id\"}}}}]}",
  )
  let expression = @lowering_relation.lower_expression(
    pipeline,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expression),
    "{\"body\":{\"index\":{\"body\":\"id\",\"op\":\"field\"},\"value\":{\"body\":[{\"body\":\"id\",\"op\":\"field\"}],\"op\":\"array\"}},\"op\":\"subscript\"}",
  )
  let kernel = @lowering_relation.prepare_kernel(
    pipeline,
    1,
    max_bindings=100,
    max_name_bytes=10000,
    expression_limits(),
  ).unwrap()
  let index = @lowering_relation.prepare_ordered_references(
    kernel,
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr/body/value/body/0\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/0/expr/body/index\",\"target\":{\"input_field\":\"id\"}}]",
  )
}
