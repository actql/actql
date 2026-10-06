///|
test "common LENGTH lowers the ordinary checked node without changing its wire" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"n\":{\"len\":{\"literal\":\"é😀\"}}}}",
  )
  let expression = match
    @lowering_relation.lower_expression(owner, 1, 0, expression_limits()) {
    Ok(expression) => expression
    Err(issue) => {
      debug_inspect(issue.kind, content="LENGTH must lower")
      fail("checked LENGTH rejected")
    }
  }
  assert_true(
    @lowering_relation.expression_body(expression)
    is @lowering_relation.Unary(@lowering_relation.Length, _),
  )
  assert_eq(
    expression_wire(expression),
    "{\"body\":{\"body\":\"é😀\",\"op\":\"literal\"},\"op\":\"len\"}",
  )
}

///|
test "common REPLACE lowers the ordinary checked ordered operands without changing its wire" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"s\":{\"replace\":[{\"literal\":\"banana\"},{\"literal\":\"ana\"},{\"literal\":\"X\"}]}}}",
  )
  let expression = match
    @lowering_relation.lower_expression(owner, 1, 0, expression_limits()) {
    Ok(expression) => expression
    Err(issue) => {
      debug_inspect(issue.kind, content="REPLACE must lower")
      fail("checked REPLACE rejected")
    }
  }
  assert_true(
    @lowering_relation.expression_body(expression)
    is @lowering_relation.Many(@lowering_relation.Replace, args) &&
    args.length() == 3,
  )
  assert_eq(
    expression_wire(expression),
    "{\"body\":[{\"body\":\"banana\",\"op\":\"literal\"},{\"body\":\"ana\",\"op\":\"literal\"},{\"body\":\"X\",\"op\":\"literal\"}],\"op\":\"replace\"}",
  )
}
