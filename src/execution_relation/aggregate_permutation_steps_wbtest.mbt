///|
test "aggregate permutation admits both arrays before one-entry steps" {
  let workspace = row_workspace(6)
  let control : ControlBudget = { remaining: 3, max_frames: 10, }
  let state = start_aggregate_permutation(
    [Number(7.0), Null, Number(2.0)],
    [1, 2, 0],
    control,
    workspace,
  )
  assert_eq(workspace.live, 0)
  assert_true(advance_aggregate_permutation(state) is Ok(None))
  assert_eq(workspace.live, 6)
  assert_eq(state.output.length(), 0)
  for index in 0..<3 {
    assert_true(advance_aggregate_permutation(state) is Ok(None))
    assert_eq(state.output.length(), index + 1)
    assert_eq(state.indices.length(), index + 1)
  }
  let (values, indices) = advance_aggregate_permutation(state).unwrap().unwrap()
  assert_true(values[0] is Null)
  assert_true(values[1] is Number(2.0))
  assert_true(values[2] is Number(7.0))
  assert_eq(indices, [0, 1, 2])
  assert_eq(control.remaining, 0)
  close_aggregate_permutation(state)
  assert_eq(values.length(), 3)
  assert_eq(workspace.live, 6)
  release_slots(workspace, 6)
}

///|
test "aggregate permutation rejects one-short space before construction" {
  let workspace = row_workspace(5)
  let control : ControlBudget = { remaining: 3, max_frames: 10, }
  let state = start_aggregate_permutation(
    [Null, Null, Null],
    [0, 1, 2],
    control,
    workspace,
  )
  assert_true(advance_aggregate_permutation(state) is Err(RowLimit))
  assert_eq(state.output.length(), 0)
  assert_eq(state.indices.length(), 0)
  assert_eq(workspace.peak, 0)
  assert_eq(control.remaining, 3)
}

///|
test "aggregate permutation failure and cancellation preserve borrowed arrays" {
  for cancel in [false, true] {
    let workspace = row_workspace(9)
    assert_true(reserve_slots(workspace, 3))
    let control : ControlBudget = { remaining: 2, max_frames: 10, }
    let values : Array[Value] = [Null, Number(1.0), Number(2.0)]
    let order = [2, 1, 0]
    let state = start_aggregate_permutation(values, order, control, workspace)
    for _ in 0..<3 {
      assert_true(advance_aggregate_permutation(state) is Ok(None))
    }
    assert_eq(state.output.length(), 2)
    if cancel {
      close_aggregate_permutation(state)
    } else {
      assert_true(advance_aggregate_permutation(state) is Err(RowLimit))
    }
    close_aggregate_permutation(state)
    assert_eq(workspace.live, 3)
    assert_eq(control.remaining, 0)
    assert_eq(values.length(), 3)
    assert_eq(order, [2, 1, 0])
    assert_eq(state.output.length(), 0)
    assert_eq(state.indices.length(), 0)
  }
}
