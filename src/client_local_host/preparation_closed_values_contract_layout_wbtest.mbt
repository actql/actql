///|
test "closed Values contract closure owns bounded graphs not per-cell copies" {
  let layout = closed_values_contract_layout().unwrap()
  assert_eq(preparation_representation_cost(layout.retained), Some(6488L))
  assert_eq(layout.retained.record_headers, 160L)
  assert_eq(layout.retained.reference_slots, 268L)
  assert_eq(layout.retained.scalar_words, 223L)
  assert_eq(layout.temporary.record_headers, 490L)
  assert_eq(layout.temporary.reference_slots, 1562L)
  assert_eq(layout.temporary.scalar_words, 736L)
  assert_eq(preparation_representation_cost(layout.temporary), Some(26224L))
  assert_eq(layout.retained.owned_utf16_units, 0L)
  assert_eq(layout.temporary.owned_wire_bytes, 0L)
}

///|
test "closed Values contract adjacency partition capacity inequalities" {
  // Exhaust each possible owner degree independently. Summing these linear
  // bounds proves the eight-owner/22-edge aggregate for every partition.
  for degree in 0..<23 {
    let map = closed_values_map_constructor_layout(degree).unwrap()
    let capacity = (map.reference_slots - 2L - 6L * degree.to_int64()) / 2L
    assert_true(capacity <= 8L + 4L * degree.to_int64())
    assert_true(
      closed_values_append_capacity(degree).unwrap() <=
      8L + 2L * degree.to_int64(),
    )
  }
}
