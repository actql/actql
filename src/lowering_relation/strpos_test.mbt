///|
test "STRPOS lowers and encodes through the existing binary owner" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"strpos\":[{\"literal\":\"😀a\"},{\"literal\":\"a\"}]}}}",
  )
  let lowered = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(lowered)
    is @lowering_relation.Binary(@lowering_relation.Strpos, _, _),
  )
  assert_eq(
    expression_wire(lowered),
    "{\"body\":[{\"body\":\"😀a\",\"op\":\"literal\"},{\"body\":\"a\",\"op\":\"literal\"}],\"op\":\"strpos\"}",
  )
}
