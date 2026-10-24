///|
test "one Values installed execution plan retains controls without copying source rows" {
  let layout=closed_values_execution_plan_controls_layout().unwrap()
  assert_eq(layout.retained.record_headers,73L)
  assert_eq(layout.retained.reference_slots,114L)
  assert_eq(layout.retained.scalar_words,133L)
  assert_eq(preparation_representation_cost(layout.retained),Some(3144L))
  assert_eq(layout.temporary.record_headers,189L)
  assert_eq(layout.temporary.reference_slots,369L)
  assert_eq(layout.temporary.scalar_words,445L)
  assert_eq(preparation_representation_cost(layout.temporary),Some(9536L))
  assert_eq(layout.retained.owned_utf16_units,0L)
  assert_eq(layout.retained.owned_wire_bytes,0L)
}
