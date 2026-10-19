///|
test "QUANTIZE emission retains static target mode and the single original typed child" {
  let owner = expression_pipeline(
    ", {\"derive\":{\"v\":\"quantize(NULL,4,2,'half_even')\"}}",
  )
  let expr = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"precision\":4,\"rounding\":\"half_even\",\"scale\":2,\"value\":{\"body\":{\"contract\":{\"nullable\":true,\"precision\":4,\"scale\":2,\"type\":\"decimal\"}},\"op\":\"typed_null\"}},\"op\":\"quantize\"}",
  )
}
