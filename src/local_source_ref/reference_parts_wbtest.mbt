///|
test "reference split retains only the complete format plus one refusal component" {
  let out = StringBuilder()
  out.write_string("source:local/s/rows")
  for _ in 0..<1000 {
    out.write_string("/unused")
  }
  let input = out.to_string()
  // Actual constructor output of the helper used by read, not an entry count.
  let parts = split_reference_parts(input)
  assert_eq(parts.length(), 4)
  assert_true(read(input, max_bytes=input.length()) is Err(InvalidReference))
}

///|
test "reference parts quantity uses the same format bound and shared collection owner" {
  // Four borrowed StringViews1H1R2W each, and the existing growing Array's
  // wrapper/backing/overlap3H25R2W. No source String copy or byte charge.
  assert_eq(reference_parts_construction_extent(), {
    record_headers: 7L,
    reference_slots: 29L,
    scalar_words: 10L,
  })
  assert_true(
    physical_equal(
      reference_parts_construction_extent(),
      reference_parts_construction_extent(),
    ),
  )
  assert_eq(split_reference_parts("a/b/c/d/e").length(), 4)
}

///|
test "reference bounded split preserves whole input byte Unicode and structural precedence" {
  let broken = String::from_array([(0xD800).unsafe_to_char()])
  let malformed = "source:local/s/rows/extra/" + broken
  assert_true(read(malformed, max_bytes=-1) is Err(InvalidLimit))
  assert_true(read(malformed, max_bytes=1) is Err(LimitExceeded))
  assert_true(read(malformed, max_bytes=1000) is Err(NonCanonicalName))
  for
    input in [
      "", "source:local/s", "source:local/s/rows/", "source:local/s/rows//", "source:local/a~9/rows/extra",
      "other:local/s/rows",
    ] {
    assert_true(read(input, max_bytes=1000) is Err(InvalidReference))
  }
  assert_true(
    read("source:local//rows", max_bytes=1000) is Err(NonCanonicalName),
  )
  assert_true(
    read("source:local/e\u{301}/rows", max_bytes=1000) is Err(NonCanonicalName),
  )
}

///|
test "reference bounded split preserves exact escaped Unicode names and one short byte refusal" {
  let text = "source:local/東京/~0~1😀"
  let original = read(text, max_bytes=1000).unwrap()
  assert_eq(stage_name(original), "東京")
  assert_eq(input_name(original), "~/😀")
  assert_eq(stringify(original), text)
  let ascii = "source:local/s/rows"
  assert_true(read(ascii, max_bytes=19) is Ok(_))
  assert_true(read(ascii, max_bytes=18) is Err(LimitExceeded))
}
