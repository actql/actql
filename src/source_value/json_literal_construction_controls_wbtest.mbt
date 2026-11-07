///|
test "literal construction follows actual nonnormalizing Unicode builder and failure controls" {
  let text = "e\u0301😀雪".repeat(100)
  let parser = Parser::make(
    "\"" + text + "\"",
    "<json-literal>",
    { max_input_bytes: 4096, max_nodes: 8, max_depth: 4, },
    normalize_text=false,
    literal_json=true,
  )
  let document = JsonDocument::make(parser)
  let mut builder_observed = false
  let mut finished = None
  for _ in 0..<100 {
    if document.string is Some((cursor, _)) && cursor.output is Some(_) {
      builder_observed = true
      assert_eq(parser.normalize_text, false)
      assert_eq(parser.literal_json, true)
    }
    let next = document.step() catch {
      _ => fail("original literal parse refused")
    }
    if next is Some(node) {
      finished = Some(node)
      break
    }
  }
  assert_true(builder_observed)
  guard finished is Some({ value: String(original), .. }) else {
    fail("expected completed original string")
  }
  assert_eq(original, text)
  let bound = json_literal_construction_extent(4096, 8, 4).unwrap()
  assert_true(bound.owned_utf16_units >= 2L * text.length().to_int64())
  let number = "0." + "0".repeat(1500) + "1"
  assert_true(
    parse_json_literal(number, {
      max_input_bytes: 4096,
      max_nodes: 8,
      max_depth: 4,
    })
    is Err({ issue: NumberPrecisionLoss, .. }),
  )
  assert_true(bound.owned_utf16_units >= 2L * number.length().to_int64())
}

///|
test "literal parser retires sibling key owners while retaining all original fields" {
  let wire = "[" + "{\"k\":1},".repeat(399) + "{\"k\":1}]"
  let limits : ParseLimits = {
    max_input_bytes: wire.length(),
    max_nodes: 1000,
    max_depth: 2,
  }
  let parser = Parser::make(
    wire,
    "<sibling-key-owners>",
    limits,
    normalize_text=false,
    literal_json=true,
  )
  let document = JsonDocument::make(parser)
  let mut peak = 0
  let mut completed = None
  for _ in 0..<10000 {
    let mut live = 0
    for frame in document.frames {
      if frame.container is ObjectFields(_, _) {
        live += 1
      }
    }
    peak = Int::max(peak, live)
    if document.step() is Some(node) {
      completed = Some(node)
      break
    }
  }
  assert_eq(peak, 1)
  guard completed is Some({ value: Array(rows), .. }) else {
    fail("Expected the same complete sibling array")
  }
  assert_eq(rows.length(), 400)
  assert_eq(document.frames.length(), 0)
  for row in rows {
    guard row.value is Object(fields) else { fail("Original object") }
    assert_eq(fields.length(), 1)
    assert_eq(fields[0].key, "k")
  }
  // The recipe bounds active owners by depth, independently of all entries.
  // Unicode text, spans, returned trees and full-node entry backing remain.
  let shallow = json_literal_construction_extent(wire.length(), 1000, 2).unwrap()
  let deep = json_literal_construction_extent(wire.length(), 1000, 1000).unwrap()
  let shallow_keys = @shape.key_admission_construction_extent(2, 1000).unwrap()
  let deep_keys = @shape.key_admission_construction_extent(1000, 1000).unwrap()
  assert_true(deep_keys.record_headers > shallow_keys.record_headers)
  assert_true(deep.record_headers > shallow.record_headers)
  assert_eq(deep.owned_utf16_units, shallow.owned_utf16_units)
}
