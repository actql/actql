///|
test "one Values installed execution plan retains controls without copying source rows" {
  let layout = closed_values_execution_plan_controls_layout().unwrap()
  assert_eq(layout.retained.record_headers, 74L)
  assert_eq(layout.retained.reference_slots, 116L)
  assert_eq(layout.retained.scalar_words, 135L)
  assert_eq(
    @execution.preparation_representation_cost(layout.retained),
    Some(3192L),
  )
  assert_eq(layout.temporary.record_headers, 230L)
  assert_eq(layout.temporary.reference_slots, 391L)
  assert_eq(layout.temporary.scalar_words, 551L)
  assert_eq(
    @execution.preparation_representation_cost(layout.temporary),
    Some(11216L),
  )
  assert_eq(layout.retained.owned_utf16_units, 0L)
  assert_eq(layout.retained.owned_wire_bytes, 0L)
}
