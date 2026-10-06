///|
test "typed JSON literal uses common typing and literal lowering for every root" {
  for
    (source, wire) in [
      ("null", "null"),
      ("true", "true"),
      ("1", "1"),
      ("\"x\"", "\"x\""),
      ("[null,1]", "[null,1]"),
      ("{\"k\":null}", "{\"k\":null}"),
    ] {
    let text = @encode.writer(1000, 1, 0)
    @encode.string_value(text, source)
    let p = expression_pipeline(
      ",{\"derive\":{\"v\":{\"typed_literal\":{\"type\":\"json\",\"value\":" +
      @encode.finish(text) +
      "}}}}",
    )
    let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
    let contract = @lowering_relation.expression_contract(expr)
    assert_true(contract.shape is @contract.Json)
    assert_eq(contract.nullable, false)
    assert_eq(
      expression_wire(expr),
      "{\"body\":{\"$json\":" + wire + "},\"op\":\"typed_literal\"}",
    )
  }
}
