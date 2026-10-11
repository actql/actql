///|
test "split lowering keeps exact authored argument order and omission" {
  for
    (source, expected) in [
      (
        "split('a,b')", "{\"body\":[{\"body\":\"a,b\",\"op\":\"literal\"}],\"op\":\"split\"}",
      ),
      (
        "split('a,b',lower(','))", "{\"body\":[{\"body\":\"a,b\",\"op\":\"literal\"},{\"body\":{\"body\":\",\",\"op\":\"literal\"},\"op\":\"lower\"}],\"op\":\"split\"}",
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
test "split delimiter references preserve input and prior-slot identities" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ",{\"derive\":[{\"s\":\"CAST(id AS string)\"},{\"d\":\"lower(s)\"},{\"parts\":\"split(s,d)\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr/body/value\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/0\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/1\",\"target\":{\"prior_slot\":1}}]",
  )
}
