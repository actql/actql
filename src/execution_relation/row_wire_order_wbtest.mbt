///|
test "row wire ordering owns names and retains source indices with bounded work" {
  let names = ["b", "a"]
  let order = prepare_row_wire_order(names, 2, 5).unwrap()
  names[1] = "changed"
  names.clear()
  assert_eq(row_wire_order_column(order, 0), Some(("a", 1)))
  assert_eq(row_wire_order_column(order, 1), Some(("b", 0)))
  assert_eq(row_wire_order_column(order, -1), None)
  assert_eq(row_wire_order_work(order), 5)
  assert_true(prepare_row_wire_order(["b", "a"], 2, 4) is Err(OrderLimit))
  assert_true(prepare_row_wire_order(["a", "a"], 2, 5) is Err(InvalidLayout))
}
