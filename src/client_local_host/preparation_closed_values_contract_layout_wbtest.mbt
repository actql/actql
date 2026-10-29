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
