///|
fn finish_document_parse(
  cursor : JsonParse,
) -> (Result[ParsedSource, ParseError], Int) raise {
  let mut total = 0
  for _ in 0..<100000 {
    match advance_json_parse(cursor, 1).unwrap() {
      JsonParseContinue(work~) => {
        assert_eq(work, 1)
        total += work
      }
      JsonParseComplete(parsed, work~) => {
        assert_eq(work, 1)
        assert_true(advance_json_parse(cursor, 1) is Err(Terminal))
        assert_eq(cursor.document.parser.source, "")
        return (Ok(parsed), total + work)
      }
      JsonParseFailed(error, work~) => {
        assert_eq(work, 1)
        assert_true(advance_json_parse(cursor, 1) is Err(Terminal))
        assert_eq(cursor.document.parser.source, "")
        return (Err(error), total + work)
      }
    }
  }
  cancel_json_parse(cursor)
  fail("document parser did not terminate")
}

///|
test "writer document removes only completed Unicode preflight work" {
  let text = String::make(4096, 'a')
  let writer = @encode.writer(5000, 2, 1)
  @encode.begin_array(writer)
  @encode.string_value(writer, text)
  @encode.end_array(writer)
  let document = @encode.finish_document(writer)
  let wire = "[\"" + text + "\"]"
  assert_eq(@encode.document_text(document), wire)
  let original = start_json_document_parse(document, limits()).unwrap()
  let copied = start_json_parse(wire, limits()).unwrap()
  assert_true(original.preflight_done)
  assert_false(copied.preflight_done)
  let (fast, fast_work) = finish_document_parse(original)
  let (raw, raw_work) = finish_document_parse(copied)
  assert_eq(raw_work - fast_work, wire.length() + 1)
  assert_true(fast_work > 1 && fast_work < 100)
  let parsed = fast.unwrap()
  assert_eq(parsed.usage, raw.unwrap().usage)
  assert_eq(parsed.usage, { input_bytes: 4100, nodes: 2, depth: 1, })
  guard parsed.node.value is Array(items) else { fail("array") }
  assert_true(items[0].value is String(actual) && actual == text)
  assert_eq(items[0].span.start_byte, 1)
  assert_eq(items[0].span.end_byte, 4099)
}

///|
test "writer document keeps tighter byte node depth and invalid bounds" {
  let writer = @encode.writer(100, 10, 5)
  @encode.begin_array(writer)
  @encode.begin_array(writer)
  @encode.null_value(writer)
  @encode.end_array(writer)
  @encode.end_array(writer)
  let document = @encode.finish_document(writer)
  let wire = "[[null]]"
  assert_eq(@encode.document_text(document), wire)
  for bound in [limits(bytes=7), limits(nodes=2), limits(depth=1)] {
    let original = start_json_document_parse(document, bound).unwrap()
    let copied = start_json_parse(wire, bound).unwrap()
    if bound.max_input_bytes == 7 {
      assert_false(original.preflight_done)
    }
    let (actual, actual_work) = finish_document_parse(original)
    let (expected, expected_work) = finish_document_parse(copied)
    assert_eq(actual.unwrap_err(), expected.unwrap_err())
    if bound.max_input_bytes == 7 {
      assert_eq(actual_work, expected_work)
    }
  }
  for bound in [limits(bytes=-1), limits(nodes=-1), limits(depth=-1)] {
    assert_eq(
      start_json_document_parse(document, bound).unwrap_err(),
      start_json_parse(wire, bound).unwrap_err(),
    )
  }
}

///|
test "writer document still applies normalized and data key duplicate rules" {
  let writer = @encode.writer(100, 10, 2)
  @encode.begin_object(writer)
  @encode.key(writer, "é")
  @encode.null_value(writer)
  @encode.key(writer, "é")
  @encode.null_value(writer)
  @encode.end_object(writer)
  let document = @encode.finish_document(writer)
  let (actual, _) = finish_document_parse(
    start_json_document_parse(document, limits()).unwrap(),
  )
  let (expected, _) = finish_document_parse(
    start_json_parse(@encode.document_text(document), limits()).unwrap(),
  )
  assert_eq(actual.unwrap_err(), expected.unwrap_err())
  let (data, _) = finish_document_parse(
    start_json_document_parse(document, limits(), data_keys=true).unwrap(),
  )
  guard data.unwrap().node.value is Object(fields) else { fail("object") }
  assert_eq(fields.map(f => f.key), ["é", "é"])
  // The completed writer itself refuses exact duplicate keys; it cannot
  // supply a document that bypasses the parser's raw duplicate-key check.
  let duplicate_writer = @encode.writer(100, 10, 2)
  @encode.begin_object(duplicate_writer)
  @encode.key(duplicate_writer, "same")
  @encode.null_value(duplicate_writer)
  let refused = try {
    @encode.key(duplicate_writer, "same")
    false
  } catch {
    @encode.InvalidStructure => true
    _ => false
  }
  assert_true(refused)
  let closed = try {
    ignore(@encode.finish_document(duplicate_writer))
    false
  } catch {
    @encode.ClosedWriter => true
    _ => false
  }
  assert_true(closed)
  let (raw_duplicate, _) = finish_document_parse(
    start_json_parse("{\"same\":null,\"same\":null}", limits(), data_keys=true).unwrap(),
  )
  assert_true(raw_duplicate.unwrap_err().issue is DuplicateKey("same"))
}

///|
test "writer document retains Unicode spans quantum and cancellation" {
  let writer = @encode.writer(10000, 2, 1)
  let text = String::make(257, 'é') + "😀\r\n"
  @encode.begin_array(writer)
  @encode.string_value(writer, text)
  @encode.end_array(writer)
  let document = @encode.finish_document(writer)
  let parser = start_json_document_parse(document, limits()).unwrap()
  assert_true(advance_json_parse(parser, 0) is Err(InvalidQuantum))
  for _ in 0..<20 {
    assert_true(advance_json_parse(parser, 1) is Ok(JsonParseContinue(..)))
    if parser.document.string is Some(_) && parser.document.parser.offset > 64 {
      break
    }
  }
  assert_true(parser.document.string is Some(_))
  cancel_json_parse(parser)
  cancel_json_parse(parser)
  assert_true(advance_json_parse(parser, 1) is Err(Terminal))
  assert_true(
    parser.document.frames.is_empty() && parser.document.string is None,
  )
  assert_eq(parser.document.parser.source, "")
  let (complete, _) = finish_document_parse(
    start_json_document_parse(document, limits()).unwrap(),
  )
  let parsed = complete.unwrap()
  assert_eq(parsed.usage.input_bytes, 2 + 257 * 2 + 4 + 4 + 2)
  guard parsed.node.value is Array(items) else { fail("array") }
  assert_true(items[0].value is String(actual) && actual == text)
  assert_eq(items[0].span.start_byte, 1)
  assert_eq(items[0].span.end_byte, parsed.usage.input_bytes - 1)
}
