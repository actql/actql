///|
fn json_literal_limits() -> ParseLimits {
  { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, }
}

///|
test "JSON data parser retains first duplicate key without changing machine syntax" {
  let input = "{\"k\":1,\"k\":2,\"nested\":{\"k\":null,\"k\":true}}"
  let parsed = parse_json_literal(input, json_literal_limits()).unwrap()
  guard parsed.node.value is Object(fields) else { fail("Object") }
  assert_eq(fields.length(), 2)
  assert_true(fields[0].value.value is Number(1.0))
  guard fields[1].value.value is Object(nested) else { fail("Object") }
  assert_eq(nested.length(), 1)
  assert_true(nested[0].value.value is Null)
  assert_true(
    parse_json(input, json_literal_limits())
    is Err({ issue: DuplicateKey("k"), .. }),
  )
  assert_eq(parsed.usage.nodes, 6)
}

///|
test "JSON data parser preserves keys and decoded strings as data" {
  let parsed = parse_json_literal(
    "{\"e\\u0301\":\"e\\u0301\\r\\n\"}",
    json_literal_limits(),
  ).unwrap()
  guard parsed.node.value is Object(fields) else { fail("Object") }
  assert_eq(fields[0].key, "e\u{0301}")
  assert_true(fields[0].value.value is String("e\u{0301}\r\n"))
}

///|
test "JSON data parser refuses loss instead of silently rounding" {
  for text in ["0.1", "1.00e2", "9007199254740992", "5e-324"] {
    assert_true(
      parse_json_literal(text, json_literal_limits()) is Ok(_),
      msg=text,
    )
  }
  for text in ["9007199254740993", "0.10000000000000001", "1e-400"] {
    assert_true(
      parse_json_literal(text, json_literal_limits())
      is Err({ issue: NumberPrecisionLoss, .. }),
      msg=text,
    )
  }
  assert_true(
    parse_json_literal("1e400", json_literal_limits())
    is Err({ issue: NumberOutOfRange, .. }),
  )
}

///|
test "JSON data parser bounds duplicate payloads bytes depth and syntax" {
  assert_true(
    parse_json_literal("{\"k\":1,\"k\":[1,2,3]}", {
      ..json_literal_limits(),
      max_nodes: 3,
    })
    is Err({ issue: NodeLimit, .. }),
  )
  assert_true(
    parse_json_literal("[[]]", { ..json_literal_limits(), max_depth: 1, })
    is Err({ issue: DepthLimit, .. }),
  )
  assert_true(
    parse_json_literal("\"日\"", {
      ..json_literal_limits(),
      max_input_bytes: 4,
    })
    is Err({ issue: InputLimit, .. }),
  )
  for text in ["{\"a\":}", "[1,]", "null true", "NaN", "\"\\ud800\""] {
    assert_true(
      parse_json_literal(text, json_literal_limits()) is Err(_),
      msg=text,
    )
  }
}
