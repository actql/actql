///|
test "substring lowering preserves optional length and named ordered wire" {
  for
    (source, expected, count) in [
      (
        "{\"substring\":{\"value\":{\"literal\":\"😀abc\"},\"start\":{\"literal\":-2}}}",
        "{\"body\":{\"start\":{\"body\":-2,\"op\":\"literal\"},\"value\":{\"body\":\"😀abc\",\"op\":\"literal\"}},\"op\":\"substring\"}",
        2,
      ),
      (
        "{\"substring\":{\"value\":{\"literal\":\"😀abc\"},\"start\":{\"literal\":0},\"length\":{\"literal\":2}}}",
        "{\"body\":{\"length\":{\"body\":2,\"op\":\"literal\"},\"start\":{\"body\":0,\"op\":\"literal\"},\"value\":{\"body\":\"😀abc\",\"op\":\"literal\"}},\"op\":\"substring\"}",
        3,
      ),
    ] {
    let owner = expression_pipeline(",{\"derive\":{\"value\":" + source + "}}")
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_true(
      @lowering_relation.expression_body(expression)
      is @lowering_relation.Many(@lowering_relation.Substring, args) &&
      args.length() == count,
    )
    assert_eq(expression_wire(expression), expected)
  }
}

///|
test "substring ordered references preserve named paths and semantic prior slots" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ", {\"derive\":[{\"old\":\"id\"},{\"text\":\"CAST(old AS string)\"},{\"suffix\":\"substring(text, old)\"},{\"slice\":\"substring(substring(text, old), old + id, id)\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body/value\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/value\",\"target\":{\"prior_slot\":1}},{\"at\":\"/bindings/2/expr/body/start\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/3/expr/body/value/body/value\",\"target\":{\"prior_slot\":1}},{\"at\":\"/bindings/3/expr/body/value/body/start\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/3/expr/body/start/body/0\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/3/expr/body/start/body/1\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/3/expr/body/length\",\"target\":{\"input_field\":\"id\"}}]",
  )
}
