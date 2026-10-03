///|
fn conditional_row_test_schema() -> @schema.ConditionalSchema {
  @schema.from_presence_fields(
    [
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=true),
        @schema.Conditional,
      ),
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        @schema.Required,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
}

///|
fn conditional_row_test_wire() -> RetainedRowDecodeLimits {
  { max_bytes: 128, max_nodes: 16, max_depth: 4, max_text_bytes: 32, }
}

///|
fn conditional_row_test_values() -> ValueLimits {
  { max_nodes: 5, max_text_bytes: 3, max_depth: 2, max_work: 8, }
}

///|
test "conditional rows roundtrip absent and explicit null separately" {
  let schema = conditional_row_test_schema()
  let examples = ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"]
  for index in 0..<examples.length() {
    let row = decode_conditional_row_wire(
      schema,
      examples[index],
      conditional_row_test_wire(),
      conditional_row_test_values(),
    ).unwrap()
    let writer = @encode.writer(128, 16, 4)
    emit_conditional_row(row, writer)
    assert_eq(@encode.finish(writer), examples[index])
    assert_true(conditional_row_cell(row, 0) is Some(Some(_)))
    assert_true(
      conditional_required_cell(row, 0)
      is Some({ value: @admitted.Number(_), .. }),
    )
    assert_true(conditional_required_cell(row, 1) is None)
    if index == 2 {
      assert_true(conditional_row_cell(row, 1) is Some(None))
    } else if index == 1 {
      assert_true(
        conditional_row_cell(row, 1)
        is Some(Some({ value: @admitted.Null, .. })),
      )
    }
  }
}

///|
test "conditional rows reject required gaps, wrong types and unknown fields" {
  let schema = conditional_row_test_schema()
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"p\":7}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(Row(MissingRequired(0))),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":\"wrong\"}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(Value(0, _)),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"other\":7}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(Decode(_)),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"id\":2}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(InvalidJson),
  )
}

///|
test "conditional presence charges absent slots and supports cancellation" {
  let schema = conditional_row_test_schema()
  let exact = decode_conditional_row_wire(
    schema,
    "{\"id\":1,\"p\":7}",
    conditional_row_test_wire(),
    conditional_row_test_values(),
  ).unwrap()
  assert_eq(conditional_row_usage(exact).nodes, 5)
  assert_eq(conditional_row_usage(exact).text_bytes, 3)
  assert_eq(conditional_row_usage(exact).work, 8)
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"p\":7}",
      conditional_row_test_wire(),
      { ..conditional_row_test_values(), max_work: 7, },
    )
    is Err(Row(Limit)),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"p\":7}",
      conditional_row_test_wire(),
      { ..conditional_row_test_values(), max_nodes: 4, },
    )
    is Err(Row(Limit)),
  )
  let builder = prepare_conditional_row(schema, conditional_row_test_values()).unwrap()
  let id_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 0).unwrap(),
  )
  let id = @admitted.checked_number_value(1.0, id_contract).unwrap()
  append_conditional_cell(builder, Some(id)).unwrap()
  assert_true(cancel_conditional_row(builder))
  assert_true(finish_conditional_row(builder) is Err(Closed))

  let invalid = prepare_conditional_row(schema, conditional_row_test_values()).unwrap()
  let wrong_contract = @contract.primitive(NumberType, nullable=false)
  let wrong = @admitted.checked_number_value(1.0, wrong_contract).unwrap()
  assert_true(
    append_conditional_cell(invalid, Some(wrong)) is Err(ForeignValue(0)),
  )
  assert_true(finish_conditional_row(invalid) is Err(Closed))
}
