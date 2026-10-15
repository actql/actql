///|
fn positional_order_value(first : Bool) -> Value {
  Captured(
    @admitted.object_value(
      Array::makei(12, index => {
        let number = match index {
          2 => if first { 1.0 } else { 2.0 }
          10 => if first { 9.0 } else { 0.0 }
          _ => 0.0
        }
        (index.to_string(), @admitted.number_value(number).unwrap())
      }),
    ).unwrap(),
  )
}

///|
test "canonical positional identity compares numeric component order without admitting ordinary object sorts" {
  let values = [positional_order_value(false), positional_order_value(true)]
  let terms = [{ column: 0, descending: false, nulls_first: false, }]
  // Component 2 decides before 10; lexical object traversal would reverse this.
  for quantum in [1, 7, 64] {
    let workspace = row_workspace(20)
    let control : ControlBudget = { remaining: 10000, max_frames: 4, }
    let state = start_stable_order(
      order_table(values),
      terms,
      control,
      workspace,
      positional_at=_ => 12,
    )
    let mut found = false
    for _ in 0..<1000 {
      if found {
        break
      }
      for _ in 0..<quantum {
        match advance_stable_order(state) {
          Ok(None) => ()
          Ok(Some(rows)) => {
            assert_eq(rows, [1, 0])
            found = true
            break
          }
          Err(_) => fail("canonical positional identity order failed")
        }
      }
    }
    assert_true(found)
    assert_eq(workspace.live, 2)
    assert_true(state.comparison.tree is None)
  }
  assert_true(
    stable_order_indices(
      order_table(values),
      terms,
      { remaining: 10000, max_frames: 4, },
      row_workspace(20),
    )
    is Err(Scalar(ComparisonDomainNotImplemented)),
  )
}

///|
test "canonical positional comparison abandons its exact cursor and rejects malformed tuples" {
  let workspace = row_workspace(20)
  assert_true(reserve_slots(workspace, 3))
  let control : ControlBudget = { remaining: 10000, max_frames: 4, }
  let state = start_stable_order(
    order_table([positional_order_value(false), positional_order_value(true)]),
    [{ column: 0, descending: false, nulls_first: false, }],
    control,
    workspace,
    positional_at=_ => 12,
  )
  for _ in 0..<100 {
    if state.comparison.tree is Some(_) {
      break
    }
    assert_true(advance_stable_order(state) is Ok(None))
  }
  let tree = state.comparison.tree.unwrap()
  let work = control.remaining
  close_stable_order(state)
  close_stable_order(state)
  assert_true(tree.closed)
  assert_true(tree.frames.is_empty())
  assert_true(state.comparison.tree is None)
  assert_eq(workspace.live, 3)
  assert_eq(control.remaining, work)
  for
    values in [
      [Number(1), Number(2)],
      [
        positional_order_value(true),
        Captured(@admitted.object_value([]).unwrap()),
      ],
    ] {
    assert_true(
      stable_order_indices(
        order_table(values),
        [{ column: 0, descending: false, nulls_first: false, }],
        { remaining: 10000, max_frames: 4, },
        row_workspace(20),
        positional_at=_ => 12,
      )
      is Err(InvalidInput),
    )
  }
}
