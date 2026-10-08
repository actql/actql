///|
test "lower retains the existing unary wire and checked string contract" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"lower\":{\"literal\":\"ΟΣ İ\"}}}}",
  )
  let expression = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(expression)
    is @lowering_relation.Unary(@lowering_relation.Lower, _),
  )
  assert_eq(
    expression_wire(expression),
    "{\"body\":{\"body\":\"ΟΣ İ\",\"op\":\"literal\"},\"op\":\"lower\"}",
  )
}
