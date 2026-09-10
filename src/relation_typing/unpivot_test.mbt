///|
test "wide repeated unpivot columns remain ordered and budgeted" {
  let columns = Array::make(10000, "\"amount\"").join(",")
  let body = cursor(
    "{\"columns\":[" +
    columns +
    "],\"name_column\":\"k\",\"value_column\":\"v\"}",
  )
  let result = check_row(Unpivot, body, input(), None, limits()).unwrap()
  match @relation_typing.reshape(result).unwrap() {
    Unpivot(columns~, ..) => assert_eq(columns.length(), 10000)
    _ => fail("expected unpivot")
  }
  assert_true(@relation_typing.work_used(result) < 200000)
}

///|
test "unpivot retains duplicate occurrences and only kept input fields" {
  let body = cursor(
    "{\"columns\":[\"amount\",\"amount\"],\"name_column\":\"id\",\"value_column\":\"v\"}",
  )
  let value = check_row(Unpivot, body, input(), None, limits()).unwrap()
  assert_eq(@schema.field_count(@relation_typing.output_schema(value)), 2)
  assert_true(field(output_row(value), "id").shape is @contract.Text(_))
  assert_true(field(output_row(value), "v").shape is @contract.Number)
  match @relation_typing.reshape(value).unwrap() {
    Unpivot(columns~, keep~, ..) => {
      assert_eq(columns.length(), 2)
      assert_eq(keep.length(), 0)
      ignore(columns.pop())
    }
    _ => fail("expected unpivot")
  }
  match @relation_typing.reshape(value).unwrap() {
    Unpivot(columns~, ..) => assert_eq(columns.length(), 2)
    _ => fail("expected unpivot")
  }
  let exact = {
    ..limits(),
    max_work: @relation_typing.work_used(value),
    max_text_bytes: @relation_typing.text_bytes_used(value),
    max_nodes: @relation_typing.nodes_used(value),
  }
  assert_true(check_row(Unpivot, body, input(), None, exact) is Ok(_))
  for
    bound in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(check_row(Unpivot, body, input(), None, bound) is Err(_))
  }
}

///|
test "unpivot checks recursive equality without narrowing values" {
  let number = @contract.primitive(NumberType, nullable=true)
  let mut child = number
  for _ in 0..<10000 {
    child = @contract.array_contract(child, nullable=false, max_items=None).unwrap()
  }
  let row = @contract.object_contract(
    [("a", child), ("b", child)],
    nullable=false,
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
  let value = check_row(
    Unpivot,
    cursor(
      "{\"columns\":[\"a\",\"b\"],\"keep\":[\"a\"],\"name_column\":\"name\",\"value_column\":\"v\"}",
    ),
    row,
    None,
    limits(),
  ).unwrap()
  assert_true(@contract.type_equal(field(output_row(value), "v"), child, 20000))
  let mismatched = schema(
    "{\"a\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}},\"b\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
  )
  let issue = check_row(
    Unpivot,
    cursor(
      "{\"columns\":[\"a\",\"b\"],\"name_column\":\"k\",\"value_column\":\"v\"}",
    ),
    mismatched,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, IncompatibleColumn("b"))
  assert_eq(issue.path, [@source.Key("columns"), Index(1)])
}
