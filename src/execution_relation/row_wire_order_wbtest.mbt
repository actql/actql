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

///|
test "row wire preparation preserves independent work and shift steps across quanta" {
  for quantum in [1, 7, 64] {
    let names = ["b", "a"]
    let cursor = start_row_wire_order(names, 2, 5).unwrap()
    assert_eq(cursor.columns.length(), 0)
    let mut steps = 0
    for _ in 0..<100 {
      let (done, used) = advance_row_wire_order(cursor, quantum).unwrap()
      assert_true(used <= quantum)
      steps += used
      if done {
        break
      }
    }
    // Five first-insertion frames, ten second-insertion/shift frames,
    // then the completion frame. Logical work remains 2 + 1 + 1 + 1.
    assert_eq(steps, 16)
    let order = finish_row_wire_order(cursor).unwrap()
    assert_eq(order.columns, [("a", 1), ("b", 0)])
    assert_eq(order.work, 5)
    assert_true(finish_row_wire_order(cursor) is Err(InvalidLayout))
    assert_true(cursor.names is None && cursor.columns.is_empty())
    names[0] = "changed"
    assert_eq(order.columns, [("a", 1), ("b", 0)])
  }
}

///|
test "row wire preparation yields within Unicode charging and common-prefix comparison" {
  let prefix = "x".repeat(1024) + "😀"
  for quantum in [1, 7, 64] {
    let cursor = start_row_wire_order([prefix + "b", prefix + "a"], 2, 2061).unwrap()
    let mut steps = 0
    for _ in 0..<4000 {
      let (done, used) = advance_row_wire_order(cursor, quantum).unwrap()
      assert_true(used <= quantum)
      steps += used
      if done {
        break
      }
    }
    let order = finish_row_wire_order(cursor).unwrap()
    assert_true(steps > 3000)
    // 2 entries + 1 comparison + twice (1024 ASCII + 4 emoji + 1 suffix).
    assert_eq(order.work, 2061)
    assert_eq(order.columns, [(prefix + "a", 1), (prefix + "b", 0)])
  }
  let short = start_row_wire_order([prefix + "b", prefix + "a"], 2, 2060).unwrap()
  let mut refused = false
  for _ in 0..<4000 {
    match advance_row_wire_order(short, 1) {
      Err(OrderLimit) => {
        refused = true
        break
      }
      Ok(_) => ()
      _ => fail("wrong one-short cause")
    }
  }
  assert_true(refused && short.closed && short.columns.is_empty())
}

///|
test "row wire preparation cancellation and duplicate refusal keep source names" {
  let names = ["x".repeat(256) + "b", "x".repeat(256) + "a"]
  let cursor = start_row_wire_order(names, 2, 1000).unwrap()
  for _ in 0..<40 {
    advance_row_wire_order(cursor, 1).unwrap() |> ignore
  }
  assert_eq(cursor.comparison.phase, 1)
  assert_true(cancel_row_wire_order(cursor))
  assert_true(!cancel_row_wire_order(cursor))
  assert_true(cursor.columns.is_empty() && cursor.names is None)
  assert_true(advance_row_wire_order(cursor, 1) is Err(InvalidLayout))
  assert_eq(names.length(), 2)
  assert_true(prepare_row_wire_order(["a", "a"], 2, 5) is Err(InvalidLayout))
  let empty = start_row_wire_order([], 0, 0).unwrap()
  assert_eq(advance_row_wire_order(empty, 1).unwrap(), (true, 1))
  assert_eq(finish_row_wire_order(empty).unwrap().work, 0)
}
