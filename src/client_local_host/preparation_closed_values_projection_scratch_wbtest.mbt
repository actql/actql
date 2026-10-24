///|
test "fixed projector controls precede all input-sized quote construction" {
  let original = closed_values_projection_scratch_units()
  assert_true(physical_equal(original, closed_values_projection_scratch_units()))
  assert_eq(original.record_headers, 4750L)
  assert_eq(original.reference_slots, 2116L)
  assert_eq(original.scalar_words, 10256L)
  assert_eq(original.owned_utf16_units, 0L)
  assert_eq(original.owned_wire_bytes, 0L)
  assert_eq(preparation_representation_cost(original), Some(174976L))
}
