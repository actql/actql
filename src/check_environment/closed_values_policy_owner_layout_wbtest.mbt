///|
test "closed Values policy owner quote is original-count bounded and rejects negative" {
  assert_eq(closed_values_policy_owner_layout(-1), None)
  let a = closed_values_policy_owner_layout(2).unwrap()
  let b = closed_values_policy_owner_layout(3).unwrap()
  assert_true(b.record_headers > a.record_headers)
  assert_true(b.reference_slots > a.reference_slots)
  assert_true(b.scalar_words > a.scalar_words)
  assert_eq(a.owned_wire_bytes, 1715L)
  assert_eq(a.owned_utf16_units, 2340L)
  // Int32 maximum field count cannot overflow this Int64 representation quote.
  let largest = closed_values_policy_owner_layout(2147483647).unwrap()
  assert_true(largest.record_headers > b.record_headers)
  assert_true(largest.scalar_words > b.scalar_words)
  // Map27 must grow beyond32:13/16 load permits only26 entries there.
  let (_, _, w26) = closed_values_policy_map_layout(26L)
  let (_, _, w27) = closed_values_policy_map_layout(27L)
  assert_eq(w27 - w26, 56L)
}
