///|
test "original UTF8 scalar and UTF16 positions remain distinct" {
  let source = @frontend_source_map.document("é\r\n😀x", 9).unwrap()
  assert_eq(@frontend_source_map.input_bytes(source), 9)
  let origin = @frontend_source_map.range(source, 4, 8).unwrap()
  assert_eq(@frontend_source_map.start(origin), {
    byte_offset: 4,
    scalar_offset: 3,
    utf16_offset: 3,
    line: 2,
    scalar_column: 1,
    utf16_column: 1,
  })
  assert_eq(@frontend_source_map.end(origin), {
    byte_offset: 8,
    scalar_offset: 4,
    utf16_offset: 5,
    line: 2,
    scalar_column: 2,
    utf16_column: 3,
  })
  assert_true(@frontend_source_map.range(source, 5, 8) is Err(InvalidRange))
  assert_true(@frontend_source_map.range(source, 8, 4) is Err(InvalidRange))
  assert_true(@frontend_source_map.range(source, 0, 10) is Err(InvalidRange))
  let span = @frontend_source_map.span(origin)
  assert_true(
    @frontend_source_map.validate_span(source, { ..span, end_column: 3, })
    is Err(InvalidSpan),
  )
  assert_true(
    @frontend_source_map.validate_span(source, { ..span, source_path: "other", })
    is Err(InvalidSpan),
  )
  let other = @frontend_source_map.document("é\r\n😀x", 9).unwrap()
  assert_false(@frontend_source_map.belongs_to(other, origin))
  assert_true(
    @frontend_source_map.document("é\r\n😀x", 8) is Err(InputLimit),
  )
  assert_true(
    @frontend_source_map.document_bytes(b"\xff", 1) is Err(InvalidUtf8),
  )
  assert_true(@frontend_source_map.document("x", -1) is Err(InvalidLimit))
}

///|
test "NFC and line endings do not rewrite the original source index" {
  let source = @frontend_source_map.document("\uFEFFe\u0301\r\nx", 9).unwrap()
  let a = @frontend_source_map.range(source, 3, 6).unwrap()
  assert_eq(@frontend_source_map.start(a).scalar_column, 1)
  assert_eq(@frontend_source_map.end(a).scalar_column, 3)
  assert_eq(@frontend_source_map.position(source, 8).unwrap().line, 2)
  assert_eq(@frontend_source_map.position(source, 8).unwrap().scalar_column, 1)
  let generated = @frontend_source_map.range(source, 3, 6, kind=Generated).unwrap()
  assert_eq(@frontend_source_map.kind(generated), Generated)
}

///|
test "original input rejects malformed UTF16 and permits zero-byte origins" {
  let bad = String::from_array([(0xd800).unsafe_to_char()])
  assert_true(@frontend_source_map.document(bad, 10) is Err(InvalidUnicode))
  let empty = @frontend_source_map.document("", 0).unwrap()
  assert_eq(
    @frontend_source_map.span(@frontend_source_map.range(empty, 0, 0).unwrap()).start_column,
    1,
  )
}
