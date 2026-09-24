///|
test "preserving JSON decode keeps external text distinct from source text" {
  let body =
    #|{"e\u0301":"line\r\nend"}
  let bytes = @utf8.encode(body)
  guard parse_json_bytes_preserving(bytes, limits()).unwrap().value
    is Object(raw_fields) &&
    parse_json_bytes(bytes, limits()).unwrap().value is Object(source_fields) else {
    fail("expected objects")
  }
  assert_eq(raw_fields[0].key, "e\u0301")
  assert_true(raw_fields[0].value.value is String("line\r\nend"))
  assert_eq(source_fields[0].key, "é")
  assert_true(source_fields[0].value.value is String("line\nend"))
}

///|
test "preserving JSON decode retains bounds and duplicate rejection" {
  let duplicate =
    #|{"key":1,"key":2}
  assert_true(
    parse_json_bytes_preserving(@utf8.encode(duplicate), limits())
    is Err({ issue: DuplicateKey("key"), .. }),
  )
  let body =
    #|{"value":"ok"}
  let bytes = @utf8.encode(body)
  assert_true(
    parse_json_bytes_preserving(bytes, limits(bytes=bytes.length() - 1))
    is Err({ issue: InputLimit, .. }),
  )
  assert_true(
    parse_json_bytes_preserving(b"\xff", limits())
    is Err({ issue: InvalidUtf8, .. }),
  )
}
