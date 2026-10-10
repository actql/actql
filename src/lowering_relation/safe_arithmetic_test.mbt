///|
test "SAFE binary operators retain both children in independent canonical wires" {
  for
    (name, op) in [
      ("safe_add", @lowering_relation.SafeAdd),
      ("safe_subtract", @lowering_relation.SafeSubtract),
      ("safe_multiply", @lowering_relation.SafeMultiply),
      ("safe_divide", @lowering_relation.SafeDivide),
    ] {
    for
      source in [
        "{\"" + name + "\":[{\"literal\":8},{\"literal\":2}]}",
        "\"" + name + "(8, 2)\"",
      ] {
      let owner = expression_pipeline(
        ",{\"derive\":{\"value\":" + source + "}}",
      )
      let expression = @lowering_relation.lower_expression(
        owner,
        1,
        0,
        expression_limits(),
      ).unwrap()
      assert_true(
        @lowering_relation.expression_body(expression)
        is @lowering_relation.Binary(actual, _, _) &&
        actual == op,
      )
      assert_eq(
        expression_wire(expression),
        "{\"body\":[{\"body\":8,\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"" +
        name +
        "\"}",
      )
    }
  }
}

///|
test "SAFE_NEGATE retains its unary node and typed NULL number contract" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"safe_negate\":{\"literal\":null}}}}",
  )
  let expression = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(expression)
    is @lowering_relation.Unary(@lowering_relation.SafeNegate, _),
  )
  assert_eq(
    expression_wire(expression),
    "{\"body\":{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},\"op\":\"safe_negate\"}",
  )
}

///|
test "SAFE arithmetic does not silently replace the legacy safe_div owner" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"safe_div\":[{\"literal\":8},{\"literal\":2}]}}}",
  )
  assert_true(
    @lowering_relation.lower_expression(owner, 1, 0, expression_limits())
    is Err(
      { kind: @lowering_relation.ExpressionNotImplemented("safe_div"), .. }
    ),
  )
}

///|
test "SAFE arithmetic ordered references preserve binary unary and prior-slot paths" {
  for op in ["safe_add", "safe_subtract", "safe_multiply", "safe_divide"] {
    let index = @lowering_relation.prepare_ordered_references(
      ordered_kernel(
        ",{\"derive\":[{\"old\":\"id\"},{\"next\":\"" +
        op +
        "(safe_negate(old), id)\"}]}",
      ),
      reference_limits(),
    ).unwrap()
    assert_eq(
      references_wire(index),
      "[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body/0/body\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/1/expr/body/1\",\"target\":{\"input_field\":\"id\"}}]",
    )
  }
}
