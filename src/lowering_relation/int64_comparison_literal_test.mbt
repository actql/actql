///|
fn int64_comparison_owner(
  expression : String,
) -> @lowering_relation.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("i"),
        @contract.primitive(@contract.Signed64Type, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let checked = @pipeline.check(
    cursor("[{\"derive\":{\"v\":" + expression + "}}]"),
    [("rows", schema)],
    None,
    Some(cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "int64 comparison lowering emits the exact annotated operand rather than Number" {
  for
    (literal, expected) in [
      ("0", "0"),
      ("-9223372036854775808", "-9223372036854775808"),
      ("9007199254740993", "9007199254740992"),
    ] {
    let owner = int64_comparison_owner(
      "{\"eq\":[{\"field\":\"i\"},{\"literal\":" + literal + "}]}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      0,
      0,
      expression_limits(),
    ).unwrap()
    guard @lowering_relation.expression_body(expression)
      is @lowering_relation.Binary(_, _, right) else {
      fail("expected equality")
    }
    guard @lowering_relation.expression_body(right)
      is @lowering_relation.Literal(value) else {
      fail("expected original typed literal")
    }
    assert_true(value.value is @value.Signed64(_))
    assert_eq(
      expression_wire(right),
      "{\"body\":\"" + expected + "\",\"op\":\"literal\"}",
    )
  }
}

///|
test "int64 comparison membership lowering keeps every exact nullable item" {
  let owner = int64_comparison_owner(
    "{\"in\":[{\"field\":\"i\"},{\"literal\":[0,9007199254740993,null]}]}",
  )
  let expression = @lowering_relation.lower_expression(
    owner,
    0,
    0,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.expression_body(expression)
    is @lowering_relation.Binary(_, _, right) else {
    fail("expected membership")
  }
  assert_eq(
    expression_wire(right),
    "{\"body\":[\"0\",\"9007199254740992\",null],\"op\":\"literal\"}",
  )
}

///|
test "int64 comparison transformed wire participates in the existing literal byte budget" {
  let owner = int64_comparison_owner(
    "{\"eq\":[{\"field\":\"i\"},{\"literal\":-9223372036854775808}]}",
  )
  assert_true(
    @lowering_relation.lower_expression(owner, 0, 0, {
      ..expression_limits(),
      max_literal_text_bytes: 19,
    })
    is Err(_),
  )
  assert_true(
    @lowering_relation.lower_expression(owner, 0, 0, {
      ..expression_limits(),
      max_literal_text_bytes: 21,
    })
    is Ok(_),
  )
}
