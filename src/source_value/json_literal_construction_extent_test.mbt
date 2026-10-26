///|
test "literal construction bound covers original Unicode escaped and duplicate Source trees" {
  let limits : ParseLimits = {
    max_input_bytes: 8192,
    max_nodes: 128,
    max_depth: 8,
  }
  let bound = json_literal_construction_extent(
    limits.max_input_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).unwrap()
  for
    wire in [
      "{\"e\\u0301\":[\"😀\",1,null],\"x\":{}}",
      "{\"same\":\"雪\",\"same\":[[1,2,3],{\"d\":true}]}",
      "[\"" + "e\\u0301雪😀".repeat(100) + "\"]",
      "[[[[[0]]]]]",
    ] {
    let parsed = parse_json_literal(wire, limits).unwrap()
    let actual = representation_extent(parsed.node, 128, 8, 100000).unwrap()
    // Actual returned tree is a lower bound on construction. The fixed
    // source-path String is borrowed; its repeated span references are not.
    assert_true(
      actual.nodes +
      actual.fields +
      actual.spans +
      actual.strings +
      2L * (actual.arrays + actual.objects) <=
      bound.record_headers,
    )
    assert_true(
      2L * actual.nodes +
      3L * actual.fields +
      actual.spans +
      actual.array_backing_slots +
      actual.object_backing_slots <=
      bound.reference_slots,
    )
    assert_true(6L * actual.spans <= bound.scalar_words)
    assert_true(
      actual.text_utf16_units - 14L * actual.spans <= bound.owned_utf16_units,
    )
  }
  let original = parse_json_literal(
    "{\"e\\u0301\":\"e\\u0301😀雪\"}", limits,
  ).unwrap()
  guard original.node.value is Object(fields) &&
    fields[0].value.value is String(text) else {
    fail("expected original Unicode string")
  }
  assert_eq(fields[0].key, "e\u0301")
  assert_eq(text, "e\u0301😀雪")
}

///|
test "literal construction bound is pre-read DATA and preserves original parser refusals" {
  assert_true(json_literal_construction_extent(0, 1, 1) is None)
  assert_true(json_literal_construction_extent(1, 0, 1) is None)
  assert_true(json_literal_construction_extent(1, 1, 0) is None)
  let small = json_literal_construction_extent(64, 8, 2).unwrap()
  let wide = json_literal_construction_extent(128, 16, 4).unwrap()
  assert_true(wide.record_headers > small.record_headers)
  assert_true(wide.reference_slots > small.reference_slots)
  assert_true(wide.scalar_words > small.scalar_words)
  assert_true(wide.owned_utf16_units > small.owned_utf16_units)
  let largest = json_literal_construction_extent(
    2147483647, 2147483647, 2147483647,
  ).unwrap()
  assert_true(largest.record_headers > 0L)
  assert_true(largest.reference_slots > 0L)
  assert_true(largest.scalar_words > 0L)
  assert_true(largest.owned_utf16_units > 0L)
  let limits : ParseLimits = {
    max_input_bytes: 4096,
    max_nodes: 8,
    max_depth: 2,
  }
  for
    wire in [
      "1e400", "-0", "9007199254740993", "\"\\ud800\"", "[[[0]]]", "{} trailing",
    ] {
    assert_true(parse_json_literal(wire, limits) is Err(_))
  }
}
