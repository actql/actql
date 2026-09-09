///|
test "BOM tabs CRLF and supplementary scalars retain original source coordinates" {
  let text = "\ufeff\t{\r\n\"😀\":\"e\\u0301\",\r\"z\":0\n}"
  let node = parse_json(text, limits(), source_path="example.aql").unwrap()
  assert_eq(node.span, {
    start_byte: 4,
    end_byte: 32,
    start_line: 1,
    start_column: 2,
    end_line: 4,
    end_column: 2,
    source_path: "example.aql",
  })
  guard node.value is Object(fields) else { fail("expected object") }
  assert_eq(fields[0].key_span, {
    start_byte: 7,
    end_byte: 13,
    start_line: 2,
    start_column: 1,
    end_line: 2,
    end_column: 4,
    source_path: "example.aql",
  })
  assert_eq(fields[0].value.span, {
    start_byte: 14,
    end_byte: 23,
    start_line: 2,
    start_column: 5,
    end_line: 2,
    end_column: 14,
    source_path: "example.aql",
  })
  assert_true(fields[0].value.value is String("é"))
  assert_eq(fields[1].value.span.start_line, 3)
  assert_eq(fields[1].value.span.start_column, 5)
  let from_bytes = parse_json_bytes(
    @utf8.encode(text),
    limits(),
    source_path="example.aql",
  ).unwrap()
  assert_eq(from_bytes.span, node.span)
}

///|
test "structural paths preserve keys without ambiguous string rendering" {
  let error = rejected("{\"a.b/😀\":[0,{\"e\\u0301\":?}]}")
  assert_eq(error.path, Some([Key("a.b/😀"), Index(1), Key("é")]))
  assert_eq(error.issue, UnexpectedToken)
  let duplicate = rejected("{\"é\":0,\"e\\u0301\":?}")
  assert_eq(duplicate.issue, DuplicateKey("é"))
  guard duplicate.location is Source(span) else { fail("expected source span") }
  assert_eq(span.start_byte, 8)
  assert_eq(span.end_byte, 17)
  assert_eq(span.start_column, 8)
  assert_eq(span.end_column, 17)
}

///|
test "invalid escape span points to the consumed escape character" {
  let error = rejected("\"\\q\"")
  assert_eq(error.issue, InvalidEscape)
  guard error.location is Source(span) else { fail("expected source span") }
  assert_eq(span.start_byte, 2)
  assert_eq(span.end_byte, 3)
  assert_eq(span.start_column, 3)
  assert_eq(span.end_column, 4)
  for
    (source, byte, width, line, column) in [
      ("[\"\\q\"]", 3, 1, 1, 4),
      ("[\r\n\"😀\\q\"]", 9, 1, 2, 4),
      ("\"\\😀\"", 2, 4, 1, 3),
      ("\"\\q", 2, 1, 1, 3),
    ] {
    let error = rejected(source)
    assert_eq(error.issue, InvalidEscape)
    guard error.location is Source(span) else { fail("expected escape span") }
    assert_eq(span.start_byte, byte)
    assert_eq(span.end_byte, byte + width)
    assert_eq(span.start_line, line)
    assert_eq(span.start_column, column)
    assert_eq(span.end_column, column + 1)
    guard parse_json_bytes(@utf8.encode(source), limits()) is Err(from_bytes) else {
      fail("expected invalid escape from bytes")
    }
    assert_eq(from_bytes, error)
  }
}

///|
test "invalid Unicode escape digits have a distinct issue and original position" {
  for (source, offset) in [("\"\\u12g4\"", 5), ("\"\\ud800\\u12g4\"", 11)] {
    let error = rejected(source)
    assert_eq(error.issue, InvalidUnicodeEscape)
    guard error.location is Source(span) else {
      fail("expected Unicode escape span")
    }
    assert_eq(span.start_byte, offset)
    assert_eq(span.end_byte, offset)
    guard parse_json_bytes(@utf8.encode(source), limits()) is Err(from_bytes) else {
      fail("expected Unicode escape rejection from bytes")
    }
    assert_eq(from_bytes, error)
  }
  assert_eq(rejected("\"\\u12").issue, UnexpectedEnd)
  assert_eq(rejected("\"\\q\"").issue, InvalidEscape)
}

///|
test "syntax errors and EOF report original source points without normalization shifts" {
  let error = rejected("[\r\n\t\"😀\",\r?]")
  guard error.location is Source(span) else { fail("expected source span") }
  assert_eq(span.start_byte, 12)
  assert_eq(span.end_byte, 12)
  assert_eq(span.start_line, 3)
  assert_eq(span.start_column, 1)
  assert_eq(error.path, Some([Index(1)]))
  guard rejected("\"a\\u12").location is Source(end) else {
    fail("expected EOF span")
  }
  assert_eq(end.start_byte, 6)
  assert_eq(end.start_column, 7)
}
