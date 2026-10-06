///|
test "unary plus preserves numeric expression lowering without duplicating its operand" {
  assert_eq(emit("+amount"), "{\"negate\":{\"negate\":{\"field\":\"amount\"}}}")
  assert_eq(
    emit("+(amount / @divisor)"),
    "{\"negate\":{\"negate\":{\"divide\":[{\"field\":\"amount\"},{\"$param\":\"divisor\"}]}}}",
  )
  assert_eq(
    emit("+CAST(@amount AS DECIMAL(8,3))"),
    "{\"negate\":{\"negate\":{\"cast\":{\"target\":{\"precision\":8,\"scale\":3,\"type\":\"decimal\"},\"value\":{\"$param\":\"amount\"}}}}}",
  )
  assert_eq(emit("+1"), "{\"literal\":1}")
  assert_true(
    lower(fixture("+'text'"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
}
