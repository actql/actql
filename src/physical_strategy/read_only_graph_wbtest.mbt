///|
test "checked graph nested projections refuse invalid indexes without array escape" {
  let rows = [[7, 11], []]
  for index in [-1, 2, 2147483647] {
    assert_true(checked_graph_rows_iter_at(rows, index) is None)
    assert_eq(checked_graph_rows_count_at(rows, index), None)
  }
  assert_eq(checked_graph_rows_iter_at(rows, 0).unwrap().to_array(), [7, 11])
  assert_eq(checked_graph_rows_count_at(rows, 0), Some(2))
  assert_eq(checked_graph_rows_iter_at(rows, 1).unwrap().to_array(), [])
  assert_eq(checked_graph_rows_count_at(rows, 1), Some(0))
}
