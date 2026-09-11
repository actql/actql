///|
test "reference codec rejects invalid limits and malformed or noncanonical names" {
  assert_true(
    @local_source_ref.create("s", "x", max_bytes=-1)
    is Err(@local_source_ref.InvalidLimit),
  )
  assert_true(
    @local_source_ref.read("source:local/s/x", max_bytes=-1)
    is Err(@local_source_ref.InvalidLimit),
  )
  for
    name in [
      "",
      "e\u{301}",
      "a\rb",
      String::from_array([(0xD800).unsafe_to_char()]),
    ] {
    assert_true(
      @local_source_ref.create(name, "x", max_bytes=1000)
      is Err(@local_source_ref.NonCanonicalName),
    )
    assert_true(
      @local_source_ref.create("s", name, max_bytes=1000)
      is Err(@local_source_ref.NonCanonicalName),
    )
  }
  assert_true(
    @local_source_ref.read(
      String::from_array([(0xD800).unsafe_to_char()]),
      max_bytes=1000,
    )
    is Err(@local_source_ref.NonCanonicalName),
  )
}
