///|
test "scalar quoted extent matches canonical escaping and Unicode widths" {
  let cases : Array[(String, Int64, Int64)] = [
    ("", 2L, 2L),
    ("a", 3L, 3L),
    ("\"\\\n\r\t\b", 14L, 14L),
    ("\u0000\u001f", 14L, 14L),
    ("é", 4L, 3L),
    ("日", 5L, 3L),
    ("😀", 6L, 4L),
    ("e\u0301", 5L, 4L),
  ]
  for (text, bytes, units) in cases {
    assert_eq(quoted_string_construction_extent(text), Some((bytes, units)))
    let output = writer(bytes.to_int(), 1, 0)
    string_value(output, text)
    let wire = finish(output)
    assert_eq(wire.length().to_int64(), units)
    assert_eq(@utf8.encode(wire).length().to_int64(), bytes)
  }
}
