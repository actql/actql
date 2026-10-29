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
