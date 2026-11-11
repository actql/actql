///|
test "existing literal extent aliases the same generic recipe without changing Unicode parser modes" {
  let limits : ParseLimits = {
    max_input_bytes: 512,
    max_nodes: 32,
    max_depth: 8,
  }
  let old : JsonLiteralConstructionExtent = json_literal_construction_extent(
    512, 32, 8,
  ).unwrap()
  let generic : JsonConstructionExtent = json_construction_extent(
    512,
    32,
    8,
    normalize_keys=false,
  ).unwrap()
  assert_eq(old, generic)
  let normalized = json_construction_extent(512, 32, 8, normalize_keys=true).unwrap()
  assert_true(normalized.record_headers > generic.record_headers)
  assert_true(normalized.owned_utf16_units > generic.owned_utf16_units)
  assert_true(json_literal_construction_extent(0, 32, 8) is None)
  assert_true(json_construction_extent(0, 32, 8, normalize_keys=true) is None)
  let wire = "{\"e\\u0301\":\"雪😀\"}"
  let literal = parse_json_literal(wire, limits).unwrap()
  guard literal.node.value is Object(literal_fields) else {
    fail("literal object")
  }
  assert_eq(literal_fields[0].key, "e\u0301")
  let canonical = parse_json(wire, limits).unwrap()
  guard canonical.value is Object(canonical_fields) else {
    fail("canonical object")
  }
  assert_eq(canonical_fields[0].key, "é")
  assert_true(parse_json("{\"é\":1,\"e\\u0301\":2}", limits) is Err(_))
}

///|
test "native normalized key backing refuses overflow after an otherwise representable output" {
  assert_true(
    captured_json_construction_extent(
      1,
      1,
      normalize_keys=true,
      key_units=2305843009213693951L,
      max_key_units=0,
    )
    is None,
  )
}
