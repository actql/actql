///|
test "closed Values map and traversal components include growth coexistence" {
  let six = closed_values_map_constructor_layout(6).unwrap()
  let seven = closed_values_map_constructor_layout(7).unwrap()
  assert_eq(six.record_headers, 27L)
  assert_eq(six.reference_slots, 54L)
  assert_eq(seven.record_headers, 31L)
  assert_eq(seven.reference_slots, 76L)
  let walk = closed_values_walk_storage_layout(9, 3).unwrap()
  assert_eq(walk.record_headers, 41L)
  assert_eq(walk.reference_slots, 99L)
  assert_eq(walk.scalar_words, 41L)
  assert_true(closed_values_walk_storage_layout(0, 0) is None)
  assert_true(closed_values_walk_storage_layout(1, 2) is None)
  assert_true(closed_values_map_constructor_layout(-1) is None)
}

///|
test "closed Values sorting bounds smaller-partition frames rather than comparisons" {
  let one = closed_values_sort_scratch_layout(1).unwrap()
  let three = closed_values_sort_scratch_layout(3).unwrap()
  let four = closed_values_sort_scratch_layout(4).unwrap()
  assert_eq(one.record_headers, 16L)
  assert_eq(three.record_headers, 24L)
  assert_eq(four.record_headers, 32L)
  let wide = closed_values_sort_scratch_layout(100).unwrap()
  assert_eq(wide.record_headers, 64L)
  assert_eq(wide.reference_slots, 96L)
  assert_eq(wide.scalar_words, 198L)
  assert_true(closed_values_sort_scratch_layout(0) is None)
}
