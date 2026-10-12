///|
test "padding and side-slice lowering retain exact ordered argument bodies" {
  for name in ["left", "right", "lpad", "rpad"] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"" + name + "('😀abc',2)\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"😀abc\",\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"" +
      name +
      "\"}",
    )
  }
  for name in ["lpad", "rpad"] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"" + name + "('😀abc',8,'é')\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"😀abc\",\"op\":\"literal\"},{\"body\":8,\"op\":\"literal\"},{\"body\":\"é\",\"op\":\"literal\"}],\"op\":\"" +
      name +
      "\"}",
    )
  }
}

///|
test "nested padding and side slices retain prior slots and canonical reference pointers" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ",{\"derive\":[{\"n\":\"id\"},{\"s\":\"CAST(n AS string)\"},{\"v\":\"lpad(right(s,n),n,s)\"},{\"w\":\"rpad(left(v,id),n,s)\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body/value\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/0/body/0\",\"target\":{\"prior_slot\":1}},{\"at\":\"/bindings/2/expr/body/0/body/1\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/1\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/2\",\"target\":{\"prior_slot\":1}},{\"at\":\"/bindings/3/expr/body/0/body/0\",\"target\":{\"prior_slot\":2}},{\"at\":\"/bindings/3/expr/body/0/body/1\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/3/expr/body/1\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/3/expr/body/2\",\"target\":{\"prior_slot\":1}}]",
  )
}
