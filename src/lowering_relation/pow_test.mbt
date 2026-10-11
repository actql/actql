///|
test "POW canonical machine node retains ordered and unfurled children" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"pow\":[{\"literal\":2},{\"literal\":3}]}}}",
  )
  let lowered = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(lowered)
    is @lowering_relation.Binary(@lowering_relation.Pow, _, _),
  )
  assert_eq(
    expression_wire(lowered),
    "{\"body\":[{\"body\":2,\"op\":\"literal\"},{\"body\":3,\"op\":\"literal\"}],\"op\":\"pow\"}",
  )
}
