///|
test "cbrt uses an independently authored unary wire contract" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"cbrt\":{\"literal\":4}}}}",
  )
  let expression = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(expression)
    is @lowering_relation.Unary(@lowering_relation.Cbrt, _),
  )
  assert_eq(
    expression_wire(expression),
    "{\"body\":{\"body\":4,\"op\":\"literal\"},\"op\":\"cbrt\"}",
  )
}
