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
