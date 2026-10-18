///|
fn signed64_cursor(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(wire, {
      max_input_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
fn signed64_limits() -> Limits {
  { max_nodes: 100, max_depth: 10, max_text_bytes: 4096, }
}

///|
test "Signed64 contract author checked and constructor retain their distinct leaf" {
  for nullable in [false, true] {
    let wire = "{\"type\":\"int64\",\"nullable\":" + nullable.to_string() + "}"
    let author = read_author(signed64_cursor(wire), signed64_limits()).unwrap()
    let checked = read_checked(signed64_cursor(wire), signed64_limits()).unwrap()
    let constructed = primitive(Signed64Type, nullable~)
    assert_true(author.shape is Signed64)
    assert_true(type_equal(author, checked, 1))
    assert_true(type_equal(author, constructed, 1))
    assert_eq(
      stringify_checked(constructed, 100, 3, 1),
      "{\"nullable\":" + nullable.to_string() + ",\"type\":\"int64\"}",
    )
    for
      legacy in [
        NumberType,
        StringType,
        BooleanType,
        DateType,
        TimestampType,
        JsonType,
      ] {
      let other = primitive(legacy, nullable~)
      assert_false(type_equal(author, other, 1))
      assert_false(assignable(author, other, 1))
      assert_false(assignable(other, author, 1))
      assert_true(join_nullability(author, other, 1) is None)
      assert_false(key_comparable(author, other))
    }
    let decimal = decimal_contract(19, 0, nullable~).unwrap()
    assert_false(type_equal(author, decimal, 1))
    assert_false(assignable(author, decimal, 1))
    assert_false(assignable(decimal, author, 1))
    assert_true(join_nullability(author, decimal, 1) is None)
    assert_false(key_comparable(author, decimal))
  }
}

///|
test "Signed64 grammar is closed without numeric or text constraints" {
  for
    extra in [
      "\"precision\":19", "\"scale\":0", "\"minimum\":0", "\"maximum\":1", "\"integer\":true",
      "\"enum\":[\"1\"]", "\"format\":\"int64\"", "\"max_utf8_bytes\":20",
    ] {
    let cursor = signed64_cursor(
      "{\"type\":\"int64\",\"nullable\":false," + extra + "}",
    )
    assert_true(read_author(cursor, signed64_limits()) is Err(_))
    assert_true(read_checked(cursor, signed64_limits()) is Err(_))
    assert_true(read_parameter_syntax(cursor, signed64_limits()) is Err(_))
  }
  for
    wire in [
      "{\"type\":\"Int64\",\"nullable\":false}", "{\"type\":\"signed64\",\"nullable\":false}",
      "{\"type\":\"int64\"}", "{\"type\":\"int64\",\"nullable\":null}",
    ] {
    assert_true(read_author(signed64_cursor(wire), signed64_limits()) is Err(_))
    assert_true(
      read_checked(signed64_cursor(wire), signed64_limits()) is Err(_),
    )
  }
  let parameter = read_parameter_syntax(
    signed64_cursor(
      "{\"type\":\"int64\",\"default\":\"9007199254740993\",\"meta\":{\"label\":\"exact\"}}",
    ),
    signed64_limits(),
  ).unwrap()
  assert_true(parameter.parameter_type.contract.shape is Signed64)
  assert_false(parameter.parameter_type.contract.nullable)
  assert_true(parameter.parameter_type.rule is Plain)
  assert_true(parameter.default_value is Some(_))
  assert_true(parameter.metadata is Some(_))
}

///|
test "Signed64 admission keeps exact semantic usage and legacy primitive bytes" {
  let cursor = signed64_cursor("{\"type\":\"int64\",\"nullable\":false}")
  let exact = { max_nodes: 1, max_depth: 0, max_text_bytes: 5, }
  let (_, nodes, bytes) = read_author_usage(cursor, exact).unwrap()
  assert_eq((nodes, bytes), (1, 5))
  assert_true(read_checked(cursor, exact) is Ok(_))
  for
    limits in [
      { max_nodes: 0, max_depth: 0, max_text_bytes: 5, },
      { max_nodes: 1, max_depth: 0, max_text_bytes: 4, },
    ] {
    assert_true(read_author(cursor, limits) is Err(_))
    assert_true(read_checked(cursor, limits) is Err(_))
  }
  assert_eq(
    stringify_checked(primitive(NumberType, nullable=false), 100, 3, 1),
    "{\"nullable\":false,\"type\":\"number\"}",
  )
  assert_eq(
    stringify_checked(primitive(StringType, nullable=false), 100, 3, 1),
    "{\"nullable\":false,\"type\":\"string\"}",
  )
  assert_eq(
    stringify_checked(
      decimal_contract(19, 0, nullable=false).unwrap(),
      100,
      5,
      1,
    ),
    "{\"nullable\":false,\"precision\":19,\"scale\":0,\"type\":\"decimal\"}",
  )
}

///|
test "Signed64 relations retain recursive nullability original extents and pair charges" {
  let plain = primitive(Signed64Type, nullable=false)
  let nullable = with_nullability(plain, true)
  assert_false(type_equal(plain, nullable, 1))
  assert_eq(assignable_usage(plain, nullable, 1), (true, 1))
  assert_eq(assignable_usage(nullable, plain, 1), (false, 1))
  assert_true(key_comparable(plain, nullable))
  let a = array_contract(plain, nullable=false, max_items=Some(2L)).unwrap()
  let b = array_contract(nullable, nullable=true, max_items=Some(4L)).unwrap()
  let (joined, pairs) = join_nullability_usage(a, b, 2)
  assert_eq(pairs, 2)
  assert_true(type_equal(joined.unwrap(), b, 2))
  assert_true(assignable(a, b, 2))
  assert_false(assignable(b, a, 2))
  assert_true(
    try {
      type_equal(a, a, 1) |> ignore
      false
    } catch {
      RelationLimit => true
      _ => false
    },
  )
  let equal = start_type_equality(a, a, 2)
  cancel_type_equality(equal)
  assert_true(
    try {
      advance_type_equality(equal) |> ignore
      false
    } catch {
      InvalidRelationLimit => true
      _ => false
    },
  )
}

///|
test "Signed64 checked emission is bounded cancellable and never a text contract" {
  let value = primitive(Signed64Type, nullable=false)
  let expected = "{\"nullable\":false,\"type\":\"int64\"}"
  assert_eq(stringify_checked(value, expected.length(), 3, 1), expected)
  for
    (bytes, nodes, depth) in [
      (expected.length() - 1, 3, 1),
      (expected.length(), 2, 1),
      (expected.length(), 3, 0),
    ] {
    assert_true(
      try {
        stringify_checked(value, bytes, nodes, depth) |> ignore
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
  }
  let writer = @encode.writer(100, 3, 1)
  let cursor = start_checked_emission(value, writer, 8)
  advance_checked_emission(cursor) |> ignore
  cancel_checked_emission(cursor)
  assert_true(
    try {
      @encode.finish(writer) |> ignore
      false
    } catch {
      @encode.ClosedWriter => true
      _ => false
    },
  )
}

///|
test "Signed64 unsupported Provider schema is refused instead of relabeled as text or Number" {
  let contract = object_contract(
    [("exact", primitive(Signed64Type, nullable=false))],
    nullable=false,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let writer = @encode.writer(4096, 100, 10)
  let cursor = start_json_schema_emission(contract, writer, 20).unwrap()
  let mut refused = false
  for _ in 0..<100 {
    match advance_json_schema_emission(cursor) {
      Err(Unsupported) => {
        refused = true
        break
      }
      Ok(false) => ()
      _ => fail("unsupported exact integer schema was weakened")
    }
  }
  assert_true(refused && cursor.closed)
}
