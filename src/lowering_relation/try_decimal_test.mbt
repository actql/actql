///|
test "TRY_DECIMAL emission retains precision scale and the single original child" {
  let owner = expression_pipeline(
    ", {\"derive\":{\"v\":\"try_decimal(NULL,4,2)\"}}",
  )
  let expr = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"precision\":4,\"scale\":2,\"value\":{\"body\":{\"contract\":{\"nullable\":true,\"precision\":4,\"scale\":2,\"type\":\"decimal\"}},\"op\":\"typed_null\"}},\"op\":\"try_decimal\"}",
  )
}
