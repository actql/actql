///|
test "GoogleSQL replacement consumes one digit and preserves literal scalars" {
  let checked = parse("$\r\ne\u{0301}\\0\\12\\\\a", limits(), syntax=GoogleSql).unwrap()
  assert_eq(part_count(checked), 4)
  assert_eq(part_at(checked, 0), Some(Literal("$\r\ne\u{0301}")))
  assert_eq(part_at(checked, 1), Some(Capture(0)))
  assert_eq(part_at(checked, 2), Some(Capture(1)))
  assert_eq(part_at(checked, 3), Some(Literal("2\\a")))
  assert_eq(part_at(checked, 4), None)
  let stats = stats(checked)
  assert_eq(
    (
      stats.literal_utf8_bytes,
      stats.capture_reference_count,
      stats.max_capture_index,
    ),
    (9, 2, 1),
  )
}

///|
test "GoogleSQL replacement rejects invalid escapes and seals a separate preimage" {
  for (text, at) in [("\\", 0), ("abc\\x", 3), ("\\é", 0)] {
    assert_true(
      parse(text, limits(), syntax=GoogleSql) is Err(InvalidReplacement(offset)) &&
      offset == at,
    )
  }
  let google = parse("plain", limits(), syntax=GoogleSql).unwrap()
  let actql = parse("plain", limits()).unwrap()
  let preimage = @encode.writer(1000, 100, 3)
  emit_preimage(google, preimage)
  assert_eq(
    @encode.finish(preimage),
    "{\"capture_reference_count\":0,\"literal_utf8_bytes\":5,\"max_capture_index\":0,\"parts\":[{\"kind\":\"literal\",\"value\":\"plain\"}],\"version\":\"actql-sql-regex-replacement-ast/0.1\"}",
  )
  assert_true(cid(google) != cid(actql))
}
