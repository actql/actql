///|
test "closed Values topology includes empty original parameter owners exactly once" {
  let layout = closed_values_topology_layout().unwrap()
  assert_eq(layout.retained.record_headers, 52L)
  assert_eq(layout.retained.reference_slots, 137L)
  assert_eq(layout.retained.scalar_words, 73L)
  assert_eq(preparation_representation_cost(layout.retained), Some(2512L))
  assert_eq(layout.retained.owned_utf16_units, 0L)
  assert_eq(layout.retained.owned_wire_bytes, 0L)
  assert_eq(layout.temporary.record_headers, 245L)
  assert_eq(layout.temporary.reference_slots, 503L)
  assert_eq(layout.temporary.scalar_words, 402L)
  assert_eq(preparation_representation_cost(layout.temporary), Some(11160L))
}
