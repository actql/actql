///|
test "Unicode scalar lowering retains fixed unary body operation tags" {
  for
    (source, expected) in [
      (
        "byte_length('😀')", "{\"body\":{\"body\":\"😀\",\"op\":\"literal\"},\"op\":\"byte_length\"}",
      ),
      (
        "octet_length('😀')", "{\"body\":{\"body\":\"😀\",\"op\":\"literal\"},\"op\":\"byte_length\"}",
      ),
      (
        "unicode('é')", "{\"body\":{\"body\":\"é\",\"op\":\"literal\"},\"op\":\"unicode\"}",
      ),
      (
        "chr(128512)", "{\"body\":{\"body\":128512,\"op\":\"literal\"},\"op\":\"chr\"}",
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
test "Unicode scalar ordered references preserve input and prior slot custody" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ",{\"derive\":[{\"character\":\"chr(id)\"},{\"code\":\"unicode(character)\"},{\"bytes\":\"byte_length(character)\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr/body\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body\",\"target\":{\"prior_slot\":0}}]",
  )
}
