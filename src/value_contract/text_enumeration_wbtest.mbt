///|
fn enumeration_cursor(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(wire, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 30,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 30,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn enumeration_contract(wire : String) -> Contract {
  read_checked(enumeration_cursor(wire), {
    max_nodes: 10000,
    max_depth: 30,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
test "Text enumeration retains exact Unicode order duplicates empty and absent bytes" {
  for values in [[], ["low", "high", "low"], ["", "e\u{0301}", "é", "a\r\nb"]] {
    let contract = string_enum_contract(
      values,
      { max_nodes: 100, max_depth: 2, max_text_bytes: 100, },
      nullable=false,
    ).unwrap()
    guard contract.shape is Text(bounds) else { fail("expected Text") }
    assert_eq(text_enumerant_count(bounds), Some(values.length()))
    for index in 0..<values.length() {
      assert_eq(text_enumerant_at(bounds, index), Some(values[index]))
    }
    assert_true(text_enumerant_at(bounds, -1) is None)
    assert_true(text_enumerant_at(bounds, values.length()) is None)
    let wire = stringify_checked(contract, 1000, 100, 4)
    let restored = enumeration_contract(wire)
    assert_true(type_equal(contract, restored, 100))
  }
  let plain = primitive(StringType, nullable=false)
  assert_eq(
    stringify_checked(plain, 100, 3, 1),
    "{\"nullable\":false,\"type\":\"string\"}",
  )
  guard plain.shape is Text(bounds) else { fail("expected Text") }
  assert_true(text_enumerant_count(bounds) is None)
}

///|
test "Text enumeration metadata has exact shared node text depth and closed admission" {
  let wire = "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"a\",\"😀\",\"a\"]}"
  let root = enumeration_cursor(wire)
  let (_, nodes, bytes) = read_checked_usage(root, {
    max_nodes: 5,
    max_depth: 2,
    max_text_bytes: 12,
  }).unwrap()
  assert_eq((nodes, bytes), (5, 12))
  for
    limits in [
      { max_nodes: 4, max_depth: 2, max_text_bytes: 12, },
      { max_nodes: 5, max_depth: 1, max_text_bytes: 12, },
      { max_nodes: 5, max_depth: 2, max_text_bytes: 11, },
    ] {
    assert_true(read_checked(root, limits) is Err(_))
  }
  for
    wire in [
      "{\"type\":\"string\",\"nullable\":false,\"enum\":null}", "{\"type\":\"string\",\"nullable\":false,\"enum\":[1]}",
      "{\"type\":\"string\",\"nullable\":false,\"enum\":[null]}", "{\"type\":\"number\",\"nullable\":false,\"enum\":[\"a\"]}",
    ] {
    assert_true(
      read_author(enumeration_cursor(wire), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 100,
      })
      is Err(_),
    )
  }
  assert_true(
    read_parameter_syntax(root, {
      max_nodes: 5,
      max_depth: 2,
      max_text_bytes: 12,
    }).unwrap().parameter_type.contract.shape
    is Text(bounds) &&
    text_enumerant_count(bounds) == Some(3),
  )
}

///|
test "Text enumeration equality binds exact vector and bounded string continuations" {
  let make = (values : Array[String]) => {
    string_enum_contract(
      values,
      { max_nodes: 20, max_depth: 2, max_text_bytes: 10000, },
      nullable=false,
    ).unwrap()
  }
  let a = make(["x".repeat(257), "a", "a"])
  assert_true(type_equal(a, make(["x".repeat(257), "a", "a"]), 100))
  assert_false(type_equal(a, make(["x".repeat(257), "a"]), 100))
  assert_false(type_equal(make(["a", "b"]), make(["b", "a"]), 100))
  assert_false(type_equal(make([]), primitive(StringType, nullable=false), 100))
  let cursor = start_type_equality(a, a, 100)
  assert_true(advance_type_equality(cursor) is None)
  assert_true(advance_type_equality(cursor) is None)
  cancel_type_equality(cursor)
  assert_true(cursor.pending.is_empty())
  assert_true(
    try {
      type_equal(a, a, 2) |> ignore
      false
    } catch {
      RelationLimit => true
      _ => false
    },
  )
}

///|
test "Text enumeration assignment intersects original extents and join is conservative" {
  let left = enumeration_contract(
    "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"a\",\"xxxx\",\"a\"],\"max_codepoints\":1}",
  )
  let right = enumeration_contract(
    "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"b\"],\"max_codepoints\":4}",
  )
  let expected = enumeration_contract(
    "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"a\"],\"max_codepoints\":1}",
  )
  assert_true(assignable(left, expected, 100))
  assert_false(assignable(right, expected, 100))
  assert_false(assignable(primitive(StringType, nullable=false), expected, 100))
  let joined = join_nullability(left, right, 100).unwrap()
  assert_eq(
    stringify_checked(joined, 1000, 100, 4),
    "{\"enum\":[\"a\",\"xxxx\",\"a\",\"b\"],\"max_codepoints\":4,\"nullable\":false,\"type\":\"string\"}",
  )
  assert_true(assignable(left, joined, 100))
  assert_true(assignable(right, joined, 100))
  let empty = string_enum_contract(
    [],
    { max_nodes: 2, max_depth: 1, max_text_bytes: 0, },
    nullable=false,
  ).unwrap()
  assert_true(assignable(empty, expected, 2))
  let broad = join_nullability(left, primitive(StringType, nullable=true), 100).unwrap()
  assert_eq(
    stringify_checked(broad, 100, 3, 1),
    "{\"nullable\":true,\"type\":\"string\"}",
  )
}

///|
test "Text enum construction detaches mutable input and checks before copying" {
  let values = ["a", "a", "b"]
  let original = string_enum_contract(
    values,
    { max_nodes: 5, max_depth: 2, max_text_bytes: 3, },
    nullable=false,
  ).unwrap()
  values[0] = "changed"
  values.push("extra")
  assert_eq(
    stringify_checked(original, 100, 20, 4),
    "{\"enum\":[\"a\",\"a\",\"b\"],\"nullable\":false,\"type\":\"string\"}",
  )
  assert_true(
    string_enum_contract(
      values,
      { max_nodes: 5, max_depth: 2, max_text_bytes: 100, },
      nullable=false,
    )
    is None,
  )
  assert_true(
    string_enum_contract(
      ["😀"],
      { max_nodes: 3, max_depth: 2, max_text_bytes: 3, },
      nullable=false,
    )
    is None,
  )
}

///|
test "Text enum checked and JSON schema emission preserve members and cancelled aliases" {
  let text = string_enum_contract(
    ["low", "high", "low"],
    { max_nodes: 5, max_depth: 2, max_text_bytes: 10, },
    nullable=true,
  ).unwrap()
  let root = object_contract(
    [("level", text)],
    nullable=false,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let writer = @encode.writer(1000, 100, 10)
  let cursor = start_json_schema_emission(root, writer, 30).unwrap()
  for _ in 0..<1000 {
    if advance_json_schema_emission(cursor).unwrap() {
      break
    }
  }
  assert_eq(
    @encode.finish(writer),
    "{\"additionalProperties\":false,\"properties\":{\"level\":{\"anyOf\":[{\"enum\":[\"low\",\"high\",\"low\"],\"type\":\"string\"},{\"type\":\"null\"}]}},\"required\":[\"level\"],\"type\":\"object\"}",
  )
  let long = string_enum_contract(
    ["x".repeat(1024)],
    { max_nodes: 3, max_depth: 2, max_text_bytes: 1024, },
    nullable=false,
  ).unwrap()
  let writer = @encode.writer(2000, 10, 4)
  let cursor = start_checked_emission(long, writer, 20)
  let mut found = false
  for _ in 0..<100 {
    advance_checked_emission(cursor) |> ignore
    if cursor.text is Some(_) {
      found = true
      break
    }
  }
  assert_true(found)
  cancel_checked_emission(cursor)
  assert_true(
    cursor.pending.is_empty() && cursor.text is None && cursor.key is None,
  )
}
