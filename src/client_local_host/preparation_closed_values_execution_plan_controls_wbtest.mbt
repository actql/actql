///|
test "one Values installed execution plan retains controls without copying source rows" {
  let layout = closed_values_execution_plan_controls_layout().unwrap()
  assert_eq(layout.retained.record_headers, 73L)
  assert_eq(layout.retained.reference_slots, 114L)
  assert_eq(layout.retained.scalar_words, 134L)
  assert_eq(
    @execution.preparation_representation_cost(layout.retained),
    Some(3152L),
  )
  assert_eq(layout.temporary.record_headers, 189L)
  assert_eq(layout.temporary.reference_slots, 369L)
  assert_eq(layout.temporary.scalar_words, 447L)
  assert_eq(
    @execution.preparation_representation_cost(layout.temporary),
    Some(9552L),
  )
  assert_eq(layout.retained.owned_utf16_units, 0L)
  assert_eq(layout.retained.owned_wire_bytes, 0L)
}
