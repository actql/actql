///|
test "strict UTF8 rejects overlong surrogate truncated and out of range sequences" {
  let bad : Array[Bytes] = [
    b"\x80", b"\xbf", b"\xc0\x80", b"\xc1\xbf", b"\xc2", b"\xc2A", b"\xe0\x9f\xbf",
    b"\xe0\xa0", b"\xe1\x80A", b"\xed\xa0\x80", b"\xed\xbf\xbf", b"\xf0\x8f\xbf\xbf",
    b"\xf0\x90\x80", b"\xf4\x90\x80\x80", b"\xf5\x80\x80\x80", b"\xff", b"\xfe",
  ]
  for bytes in bad {
    for prefix in [b"", b"\xef\xbb\xbf", b" \"\xc3\xa9"] {
      let input = prefix + bytes
      guard parse_json_bytes(input, limits(), source_path="bad.json")
        is Err(error) else {
        fail("expected malformed UTF8")
      }
      assert_eq(error.issue, InvalidUtf8)
      assert_eq(error.location, ByteOffset(prefix.length()))
      assert_eq(error.path, None)
      assert_eq(error.source_path, "bad.json")
    }
  }
}

///|
test "UTF8 scalar endpoints and literal replacement character remain valid" {
  for
    text in [
      "\u007f", "\u0080", "\u07ff", "\u0800", "\ud7ff", "\ue000", "\uffff", "\u{10000}",
      "\u{10ffff}", "�",
    ] {
    let source = "\"" + text + "\""
    let bytes = @utf8.encode(source)
    guard parse_json_bytes(bytes, limits(bytes=bytes.length())).unwrap().value
      is String(actual) else {
      fail("expected string")
    }
    assert_eq(actual, text)
  }
}

///|
test "one leading BOM is accepted without hiding extra BOMs or later documents" {
  let source = "\ufeff \r\n{\"a\":1}"
  assert_true(parsed(source).value is Object(_))
  assert_true(
    parse_json_bytes(@utf8.encode(source), limits()).unwrap().value is Object(_),
  )
  for
    text in ["\ufeff\ufeff{}", " \ufeff{}", "{}\ufeff", "\ufeff", "\ufeff{} {}"] {
    assert_true(parse_json(text, limits()) is Err(_))
    assert_true(parse_json_bytes(@utf8.encode(text), limits()) is Err(_))
  }
  assert_true(parsed("\"\ufeff\"").value is String("\ufeff"))
}

///|
test "input preflight has explicit size encoding and setting precedence" {
  let high = String::from_array([(0xd800).unsafe_to_char()])
  let low = String::from_array([(0xdc00).unsafe_to_char()])
  for malformed in [high, low] {
    let source = "a😀" + malformed
    guard parse_json(source, limits()) is Err(error) else {
      fail("expected invalid UTF16")
    }
    assert_eq(error.issue, InvalidUtf16)
    assert_eq(error.location, Utf16Offset(3))
    assert_eq(error.path, None)
    assert_true(
      parse_json(source, limits(bytes=0)) is Err({ issue: InputLimit, .. }),
    )
  }
  for
    bound in [
      limits(bytes=-1),
      limits(bytes=2147483647),
      limits(nodes=-1),
      limits(depth=-1),
    ] {
    assert_true(parse_json(high, bound) is Err({ issue: InvalidLimits, .. }))
    assert_true(
      parse_json_bytes(b"\xff", bound) is Err({ issue: InvalidLimits, .. }),
    )
  }
  assert_true(
    parse_json_bytes(b"\xff", limits(bytes=0)) is Err({ issue: InputLimit, .. }),
  )
  assert_true(parse_json("0", limits(bytes=2147483646)) is Ok(_))
  // Preflight examines the whole encoding before JSON grammar.
  assert_true(
    parse_json_bytes(b"?\xff", limits()) is Err({ issue: InvalidUtf8, .. }),
  )
  assert_true(
    parse_json("?" + high, limits()) is Err({ issue: InvalidUtf16, .. }),
  )
}
