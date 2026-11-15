///|
test "YAML current document construction keeps node policy separate from physical lines and text" {
  let json = json_literal_construction_extent(1024, 32, 8).unwrap()
  let yaml = yaml_literal_construction_extent(1024, 32, 8, 4).unwrap()
  assert_eq(yaml.record_headers - json.record_headers, 9L * 9L + 2L * 4L + 8L)
  assert_eq(
    yaml.reference_slots - json.reference_slots,
    16L * 9L + 3L * 4L + 12L,
  )
  assert_eq(yaml.scalar_words - json.scalar_words, 24L * 9L + 2L * 4L + 8L)
  assert_eq(yaml.owned_utf16_units - json.owned_utf16_units, 8L * 1024L)
  assert_true(yaml_literal_construction_extent(1024, 32, 8, 1026) is None)
  assert_true(yaml_literal_construction_extent(1024, 0, 8, 4) is None)
  assert_true(yaml_literal_construction_extent(1024, 32, 0, 4) is None)
}
