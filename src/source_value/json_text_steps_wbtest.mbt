///|
test "resumed JSON yields inside data Text and whitespace without changing spans" {
  let text = String::make(257, 'é') + "😀\r\n"
  let wire = "[\"" +
    String::make(257, 'é') +
    "😀\\r\\n\"]" +
    String::make(129, ' ')
  let parser = start_json_parse(wire, limits(), data_keys=true).unwrap()
  let mut parsed : ParsedSource? = None
  let mut transitions = 0
  for _ in 0..<10000 {
    let before = parser.document.parser.offset
    match advance_json_parse(parser, 1).unwrap() {
      JsonParseContinue(work~) => {
        assert_eq(work, 1)
        let after = parser.document.parser.offset
        assert_true(after - before <= 64 * 12)
        if before > 0 && parser.document.string is Some(_) {
          transitions += 1
        }
      }
      JsonParseComplete(value, work~) => {
        assert_eq(work, 1)
        parsed = Some(value)
        break
      }
      JsonParseFailed(_, ..) => fail("valid Text rejected")
    }
  }
  assert_true(transitions >= 4)
  guard parsed.unwrap().node.value is Array(items) else { fail("array") }
  guard items[0].value is String(actual) else { fail("text") }
  assert_eq(actual, text)
  assert_eq(items[0].span.start_byte, 1)
  // Opening quote, 257 two-byte scalars, one emoji, escapes, closing quote.
  assert_eq(items[0].span.end_byte, 2 + 257 * 2 + 4 + 4 + 1)
  assert_eq(
    parsed.unwrap().usage.input_bytes,
    2 + 257 * 2 + 4 + 4 + 1 + 1 + 129,
  )
  assert_eq(parsed.unwrap().usage.nodes, 2)
}

///|
test "resumed JSON cancellation releases a partially decoded long string" {
  let wire = "[\"" + String::make(257, 'é') + "\"]"
  let parser = start_json_parse(wire, limits(), data_keys=true).unwrap()
  for _ in 0..<10000 {
    assert_true(advance_json_parse(parser, 1) is Ok(JsonParseContinue(..)))
    if parser.document.string is Some(_) && parser.document.parser.offset > 64 {
      break
    }
  }
  assert_true(parser.document.string is Some(_))
  cancel_json_parse(parser)
  assert_true(parser.document.string is None)
  assert_true(parser.document.frames.is_empty())
  assert_true(advance_json_parse(parser, 1) is Err(Terminal))
}
