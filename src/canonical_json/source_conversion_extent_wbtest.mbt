///|
test "original canonical Source conversion keeps independent tree and text quantities" {
  let small = source_conversion_construction_extent(7, 3, 2, 1, 3, 7).unwrap()
  let text = source_conversion_construction_extent(7, 3, 2, 1, 3, 70).unwrap()
  assert_eq(small.retained, text.retained)
  assert_true(text.retained_utf16_units > small.retained_utf16_units)
  assert_true(text.scratch_utf16_units > small.scratch_utf16_units)
  let tree = source_conversion_construction_extent(70, 3, 2, 1, 3, 7).unwrap()
  assert_true(tree.retained.record_headers > small.retained.record_headers)
  assert_eq(tree.retained_utf16_units, small.retained_utf16_units)
  assert_true(source_conversion_construction_extent(7, 8, 2, 1, 3, 7) is None)
  assert_true(source_conversion_construction_extent(7, 3, 2, 1, 3, -1) is None)
}
