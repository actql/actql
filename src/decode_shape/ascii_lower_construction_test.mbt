///|
test "pinned ASCII lower construction keeps nonASCII and exact original width" {
  for
    (input, expected) in [
      ("A😀B", "a😀b"),
      ("Éİß", "Éİß"),
      ("", ""),
      ("already", "already"),
    ] {
    let value = input.to_lower()
    assert_eq(value, expected)
    let q = ascii_lower_construction_extent(input.length()).unwrap()
    assert_eq(value.length().to_int64(), q.max_output_utf16_units)
    assert_true(q.owned_utf16_units >= 2L * value.length().to_int64())
    assert_eq(
      (q.record_headers, q.reference_slots, q.scalar_words),
      (14L, 10L, 12L),
    )
  }
  assert_true(ascii_lower_construction_extent(-1) is None)
  assert_eq(
    ascii_lower_construction_extent(2147483647).unwrap().owned_utf16_units,
    6442450943L,
  )
}
