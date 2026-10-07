///|
test "array constructors use normative array and typed empty array nodes" {
  for
    (source, wire) in [
      (
        (
          #|{"array":[{"literal":2},{"literal":1},{"literal":2}]}
        ),
        (
          #|{"body":[{"body":2,"op":"literal"},{"body":1,"op":"literal"},{"body":2,"op":"literal"}],"op":"array"}
        ),
      ),
      (
        (
          #|{"empty_array":{"items":{"type":"string","nullable":false}}}
        ),
        (
          #|{"body":{"items":{"nullable":false,"type":"string"}},"op":"empty_array"}
        ),
      ),
    ] {
    let p = expression_pipeline(",{\"derive\":{\"v\":" + source + "}}")
    let lowered = @lowering_relation.lower_expression(
      p,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(expression_wire(lowered), wire)
  }
}

///|
test "array constructor child views cannot mutate the admitted expression" {
  let p = expression_pipeline(
    ",{\"derive\":{\"v\":{\"array\":[{\"field\":\"id\"},{\"field\":\"id\"}]}}}",
  )
  let lowered = @lowering_relation.lower_expression(
    p,
    1,
    0,
    expression_limits(),
  ).unwrap()
  let before = expression_wire(lowered)
  assert_eq(@lowering_relation.expression_view_entries(lowered), 2)
  guard @lowering_relation.expression_body(lowered)
    is @lowering_relation.Array(children) else {
    fail("array")
  }
  children.clear()
  assert_eq(expression_wire(lowered), before)
  assert_eq(@lowering_relation.expression_view_entries(lowered), 2)
}
