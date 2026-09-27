///|
test "aggregate preparation retains one owner across all intermediate phases" {
  for target in 0..<6 {
    let input = row_capture(row_owner(""))
    let workspace = row_workspace(100)
    assert_true(reserve_slots(workspace, 3))
    let control : ControlBudget = { remaining: 1000, max_frames: 100, }
    let state = start_aggregate_preparation(
      input,
      ["a", "b"],
      [0, 1],
      { representative: Some(0), start: 0, end: 2, },
      AggregateInputField(0),
      None,
      0,
      if target == 2 {
        []
      } else {
        [{ column: 0, descending: false, nulls_first: false, }]
      },
      control,
      workspace,
      None,
    )
    let mut reached = false
    for _ in 0..<200 {
      if !reached {
        reached = state.phase == target
        if !reached {
          assert_true(advance_aggregate_preparation(state) is Ok(None))
        }
      }
    }
    assert_true(reached)
    // Include an advance inside the phase, not only entry to that phase.
    assert_true(advance_aggregate_preparation(state) is Ok(None))
    let remaining = control.remaining
    close_aggregate_preparation(state)
    close_aggregate_preparation(state)
    assert_eq(workspace.live, 3)
    assert_eq(control.remaining, remaining)
    assert_true(advance_aggregate_preparation(state) is Err(InvalidRows))
  }
}

///|
test "aggregate preparation sorts source rows without changing argument values" {
  let input = row_capture(row_owner(""))
  let workspace = row_workspace(100)
  let state = start_aggregate_preparation(
    input,
    ["id", "b"],
    [0, 1],
    { representative: Some(0), start: 0, end: 2, },
    AggregateInputExpression(lowered("\"id + 10\"")),
    None,
    0,
    [{ column: 0, descending: false, nulls_first: false, }],
    { remaining: 1000, max_frames: 100, },
    workspace,
    Some(expression_roots(test_logical_budget(1000L, 1000L), 100)),
  )
  let mut result = None
  for _ in 0..<200 {
    if result is None {
      result = advance_aggregate_preparation(state).unwrap()
    }
  }
  let (values, indices) = result.unwrap()
  assert_true(values[0] is Number(10))
  assert_true(values[1] is Number(11))
  assert_eq(indices, [0, 1])
  close_aggregate_preparation(state)
  assert_eq(values.length(), 2)
  release_slots(workspace, workspace.live)
}

///|
test "aggregate preparation bounds structural work per advance" {
  for ordered in [false, true] {
    let input = row_capture(row_owner(""))
    let control : ControlBudget = { remaining: 1000, max_frames: 100, }
    let workspace = row_workspace(100)
    let state = start_aggregate_preparation(
      input,
      ["id", "b"],
      [0, 1],
      { representative: Some(0), start: 0, end: 2, },
      AggregateInputField(0),
      None,
      0,
      if ordered {
        [{ column: 0, descending: false, nulls_first: false, }]
      } else {
        []
      },
      control,
      workspace,
      None,
    )
    let mut result = None
    for _ in 0..<200 {
      if result is None {
        let before = control.remaining
        result = advance_aggregate_preparation(state).unwrap()
        assert_true(before - control.remaining <= 1)
      }
    }
    assert_eq(result.unwrap().0.length(), 2)
    close_aggregate_preparation(state)
    // Successful arrays belong to the enclosing aggregate until its scope ends.
    release_slots(workspace, workspace.live)
    assert_eq(workspace.live, 0)
  }
}
