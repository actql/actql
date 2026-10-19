///|
test "DECIMAL_DIVIDE emission retains exact target mode and original child order" {
  let owner = expression_pipeline(
    ", {\"derive\":{\"v\":\"decimal_divide(NULL,NULL,4,2,'half_even')\"}}",
  )
  let expr = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"left\":{\"body\":{\"contract\":{\"nullable\":true,\"precision\":4,\"scale\":2,\"type\":\"decimal\"}},\"op\":\"typed_null\"},\"precision\":4,\"right\":{\"body\":{\"contract\":{\"nullable\":true,\"precision\":4,\"scale\":2,\"type\":\"decimal\"}},\"op\":\"typed_null\"},\"rounding\":\"half_even\",\"scale\":2},\"op\":\"decimal_divide\"}",
  )
}
