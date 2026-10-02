///|
test "builder preserves decoded string scalars and their exact byte bounds" {
  let document = @origin.document("fixture", 20).unwrap()
  let origin = @origin.range(document, 0, 7).unwrap()
  for
    (value, bytes) in [
      ("\r", 1),
      ("\n", 1),
      ("\r\n", 2),
      ("é", 2),
      ("e\u{0301}", 3),
      ("\\n", 2),
    ] {
    let b = @program_source_builder.create(document, {
      ..limits(),
      tree: { ..limits().tree, max_string_bytes: bytes, },
    }).unwrap()
    let n = @program_source_builder.add(b, String(value), origin).unwrap()
    let s = @program_source_builder.finish(b, n).unwrap()
    assert_eq(@wire.text(@program_source_builder.cursor(s)), Ok(value))
    let short = @program_source_builder.create(document, {
      ..limits(),
      tree: { ..limits().tree, max_string_bytes: bytes - 1, },
    }).unwrap()
    assert_true(
      @program_source_builder.add(short, String(value), origin)
      is Err(StringLimit),
    )
  }
}
