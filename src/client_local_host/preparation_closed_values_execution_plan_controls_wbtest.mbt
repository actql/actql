///|
test "one Values installed execution plan retains controls without copying source rows" {
  let layout=closed_values_execution_plan_controls_layout().unwrap()
  assert_eq(layout.retained.record_headers,70L)
  assert_eq(layout.retained.reference_slots,109L)
  assert_eq(layout.retained.scalar_words,129L)
  assert_eq(preparation_representation_cost(layout.retained),Some(3024L))
  assert_eq(layout.temporary.record_headers,181L)
  assert_eq(layout.temporary.reference_slots,358L)
  assert_eq(layout.temporary.scalar_words,434L)
  assert_eq(preparation_representation_cost(layout.temporary),Some(9232L))
  assert_eq(layout.retained.owned_utf16_units,0L)
  assert_eq(layout.retained.owned_wire_bytes,0L)
}
