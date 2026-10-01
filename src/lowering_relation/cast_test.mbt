///|
test "CAST emission retains NULL and same-type nodes under the normative target" {
  let p = expression_pipeline(", {\"derive\":{\"v\":\"CAST(NULL AS string)\"}}")
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"target\":{\"type\":\"string\"},\"value\":{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"string\"}},\"op\":\"typed_null\"}},\"op\":\"cast\"}",
  )
  let p = expression_pipeline(
    ", {\"derive\":{\"v\":{\"cast\":{\"value\":{\"field\":\"id\"},\"target\":{\"type\":\"number\"}}}}}",
  )
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"target\":{\"type\":\"number\"},\"value\":{\"body\":\"id\",\"op\":\"field\"}},\"op\":\"cast\"}",
  )
}

///|
test "CAST bound references retain the value path and prior slot identity" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ", {\"derive\":[{\"old\":\"id\"},{\"v\":\"CAST(old AS string)\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body/value\",\"target\":{\"prior_slot\":0}}]",
  )
}

///|
test "CAST decimal target retains precision scale without nullable decoration" {
  let owner = expression_pipeline(
    ", {\"derive\":{\"v\":\"CAST(NULL AS decimal(6,2))\"}}",
  )
  let expr = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"target\":{\"precision\":6,\"scale\":2,\"type\":\"decimal\"},\"value\":{\"body\":{\"contract\":{\"nullable\":true,\"precision\":6,\"scale\":2,\"type\":\"decimal\"}},\"op\":\"typed_null\"}},\"op\":\"cast\"}",
  )
}
