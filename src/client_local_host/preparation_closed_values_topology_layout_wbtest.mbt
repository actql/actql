///|
test "closed Values topology includes empty original parameter owners exactly once" {
  let layout = closed_values_topology_layout().unwrap()
  assert_eq(layout.retained.record_headers, 53L)
  assert_eq(layout.retained.reference_slots, 139L)
  assert_eq(layout.retained.scalar_words, 77L)
  assert_eq(
    @execution.preparation_representation_cost(layout.retained),
    Some(2576L),
  )
  assert_eq(layout.retained.owned_utf16_units, 0L)
  assert_eq(layout.retained.owned_wire_bytes, 0L)
  assert_eq(layout.temporary.record_headers, 246L)
  assert_eq(layout.temporary.reference_slots, 505L)
  assert_eq(layout.temporary.scalar_words, 406L)
  assert_eq(
    @execution.preparation_representation_cost(layout.temporary),
    Some(11224L),
  )
}
