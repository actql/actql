///|
test "closed Values graph control prices only the four original leaf graphs" {
  for (n,h,r,w) in [(0,16L,31L,17L),(1,21L,54L,40L),(2,26L,61L,47L)] {
    let v=closed_values_leaf_graph_layout(n).unwrap()
    assert_eq(v.record_headers,h)
    assert_eq(v.reference_slots,r)
    assert_eq(v.scalar_words,w)
  }
  assert_true(closed_values_leaf_graph_layout(-1) is None)
  assert_true(closed_values_leaf_graph_layout(3) is None)
  let all=closed_values_graph_control_layout().unwrap()
  assert_eq(all.retained.record_headers,179L)
  assert_eq(all.retained.reference_slots,373L)
  assert_eq(all.retained.scalar_words,276L)
  assert_eq(preparation_representation_cost(all.retained),Some(8056L))
  assert_eq(all.temporary.record_headers,248L)
  assert_eq(all.temporary.reference_slots,514L)
  assert_eq(all.temporary.scalar_words,451L)
  assert_eq(preparation_representation_cost(all.temporary),Some(11688L))
}
