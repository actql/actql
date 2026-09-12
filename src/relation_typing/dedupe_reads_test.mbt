///|
test "indexed dedupe reads retain occurrences and source without exposing arrays" {
  let checked = row_checked(
    DedupeRows,
    "{\"by\":[\"id\",\"id\",\"amount\"],\"order_by\":[{\"amount\":\"desc\"},{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"amount\":\"desc\"}]}",
  )
  guard @relation_typing.row_operation(checked) is Some(DedupeRows(by~, order~)) else {
    abort("dedupe")
  }
  assert_eq(@relation_typing.dedupe_key_count(checked), 3)
  assert_eq(@relation_typing.dedupe_order_count(checked), 3)
  for i in 0..<3 {
    let key = @relation_typing.dedupe_key_at(checked, i).unwrap()
    assert_eq(key.field, by[i].field)
    assert_true(physical_equal(key.source, by[i].source))
    let term = @relation_typing.dedupe_order_at(checked, i).unwrap()
    assert_eq(term.field, order[i].field)
    assert_eq(term.direction, order[i].direction)
    assert_eq(term.nulls, order[i].nulls)
    assert_eq(term.explicit_nulls, order[i].explicit_nulls)
    assert_true(physical_equal(term.source, order[i].source))
  }
  for i in [-1, 3, 2147483647] {
    assert_true(@relation_typing.dedupe_key_at(checked, i) is None)
    assert_true(@relation_typing.dedupe_order_at(checked, i) is None)
  }
  by.clear()
  order.clear()
  assert_eq(@relation_typing.dedupe_key_count(checked), 3)
  assert_eq(@relation_typing.dedupe_order_count(checked), 3)
  assert_eq(
    @relation_typing.dedupe_key_at(checked, 1).unwrap().field,
    Unqualified("id"),
  )
  assert_eq(@relation_typing.dedupe_order_at(checked, 1).unwrap().nulls, First)
  assert_eq(@relation_typing.ranking_term_count(checked), 0)
  assert_true(@relation_typing.ranking_term_at(checked, 0) is None)
  let global = row_checked(
    DedupeRows,
    "{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}",
  )
  assert_eq(@relation_typing.dedupe_key_count(global), 0)
  assert_true(@relation_typing.dedupe_key_at(global, 0) is None)
  assert_eq(@relation_typing.dedupe_order_count(global), 1)
  let other = row_checked(Sort, "[{\"id\":\"asc\"}]")
  assert_eq(@relation_typing.dedupe_key_count(other), 0)
  assert_eq(@relation_typing.dedupe_order_count(other), 0)
  assert_true(@relation_typing.dedupe_key_at(other, 0) is None)
  assert_true(@relation_typing.dedupe_order_at(other, 0) is None)
}
