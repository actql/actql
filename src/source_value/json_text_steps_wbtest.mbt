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

///|
test "ASCII string spans keep the original scalar quantum and mixed positions" {
  for size in [63, 64, 65, 129] {
    let prefix = String::make(size, 'a')
    let wire = "\"" + prefix + "😀é\\nZ\""
    let parser = Parser::make(wire, "span.json", limits(), normalize_text=false)
    let cursor = parser.start_string([])
    assert_true(cursor.advance(parser, []) is None)
    if size == 63 {
      assert_eq(parser.offset, 66)
      assert_eq(parser.byte_offset, 68)
    } else {
      assert_eq(parser.offset, 65)
      assert_eq(parser.byte_offset, 65)
    }
    assert_eq(parser.column, 66)
    assert_eq(parser.line, 1)
    let mut result : (String, Span)? = None
    for _ in 0..<4 {
      if cursor.advance(parser, []) is Some(value) {
        result = Some(value)
        break
      }
    }
    let (text, span) = result.unwrap()
    assert_eq(text, prefix + "😀é\nZ")
    assert_eq(span.start_byte, 0)
    assert_eq(span.end_byte, size + 11)
    assert_eq(span.end_line, 1)
    assert_eq(span.end_column, size + 8)
  }
}

///|
test "ASCII string span stops before control failure and preserves its location" {
  for size in [63, 64, 65] {
    let wire = "\"" + String::make(size, 'a') + "\n\""
    let parser = Parser::make(
      wire,
      "control.json",
      limits(),
      normalize_text=false,
    )
    let cursor = parser.start_string([])
    let mut failed = false
    for _ in 0..<3 {
      ignore(cursor.advance(parser, [])) catch {
        ParseAbort(error) => {
          assert_true(error.issue is InvalidString)
          assert_eq(parser.offset, size + 1)
          assert_eq(parser.byte_offset, size + 1)
          assert_eq(parser.line, 1)
          assert_eq(parser.column, size + 2)
          failed = true
          break
        }
      }
    }
    assert_true(failed)
  }
}

///|
test "short plain JSON strings complete without a builder" {
  for text in ["", "name", String::make(63, 'a'), "é😀"] {
    let parser = Parser::make(
      "\"" + text + "\"",
      "plain.json",
      limits(),
      normalize_text=false,
    )
    let cursor = parser.start_string([])
    assert_true(cursor.output is None)
    let (decoded, span) = cursor.advance(parser, []).unwrap()
    assert_eq(decoded, text)
    assert_true(cursor.output is None)
    assert_eq(span.start_byte, 0)
    assert_eq(span.end_byte, @utf8.encode(text).length() + 2)
  }
  let parser = Parser::make("\"é\"", "key.json", limits())
  let cursor = parser.start_string([], key=true)
  let (decoded, _) = cursor.advance(parser, []).unwrap()
  assert_eq(decoded, "é")
  assert_true(cursor.output is None)
}

///|
test "JSON builder starts before yield or escape with the exact original prefix" {
  for size in [0, 63, 64, 65, 129] {
    let prefix = String::make(size, 'a')
    let parser = Parser::make(
      "\"" + prefix + "\\nZ\"",
      "escape.json",
      limits(),
      normalize_text=false,
    )
    let cursor = parser.start_string([])
    assert_true(cursor.output is None)
    let mut result : (String, Span)? = None
    for _ in 0..<5 {
      match cursor.advance(parser, []) {
        None => assert_true(cursor.output is Some(_))
        Some(value) => {
          result = Some(value)
          break
        }
      }
    }
    assert_eq(result.unwrap().0, prefix + "\nZ")
    assert_true(cursor.output is Some(_))
  }
}

///|
test "JSON lazy prefix materialization stays inside the original scalar quantum" {
  let text = String::make(65, '😀')
  let parser = Parser::make(
    "\"" + text + "\"",
    "quantum.json",
    limits(),
    normalize_text=false,
  )
  let cursor = parser.start_string([])
  assert_true(cursor.advance(parser, []) is None)
  assert_eq(parser.offset, 129)
  assert_eq(parser.byte_offset, 257)
  assert_eq(parser.column, 66)
  assert_true(cursor.output is Some(_))
  assert_eq(cursor.output.unwrap().to_string(), String::make(64, '😀'))
  let (decoded, span) = cursor.advance(parser, []).unwrap()
  assert_eq(decoded, text)
  assert_eq(span.end_byte, 262)
}
