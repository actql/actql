///|
test "stepped aggregate collection preserves member order and ownership" {
  let input = row_capture(row_owner(""))
  let workspace = row_workspace(100)
  let state = start_aggregate_contributors(
    input,
    ["a", "b"],
    [1, 0],
    { representative: Some(1), start: 0, end: 2, },
    AggregateInputField(0),
    None,
    0,
    { remaining: 1000, max_frames: 100, },
    workspace,
    None,
  )
  assert_eq(workspace.live, 0)
  assert_true(advance_aggregate_contributors(state) is Ok(None))
  assert_eq(state.values.length(), 0)
  assert_true(advance_aggregate_contributors(state) is Ok(None))
  assert_eq(state.values.length(), 1)
  assert_eq(workspace.live, 2)
  assert_true(advance_aggregate_contributors(state) is Ok(None))
  assert_true(advance_aggregate_contributors(state) is Ok(None))
  let (sources, values) = advance_aggregate_contributors(state)
    .unwrap()
    .unwrap()
  assert_eq(sources, [1, 0])
  assert_true(values[0] is Number(0.0))
  assert_true(values[1] is Number(1.0))
  assert_eq(workspace.live, 4)
  close_aggregate_contributors(state)
  // Success transfers the arrays and their slots to the enclosing aggregate.
  assert_eq(values.length(), 2)
  assert_eq(workspace.live, 4)
  release_slots(workspace, 4)
}

///|
test "stepped aggregate filter skips undemanded failing arguments" {
  let input = row_capture(row_owner(""))
  let workspace = row_workspace(100)
  let logical = test_logical_budget(1000L, 1000L)
  let state = start_aggregate_contributors(
    input,
    ["a", "b"],
    [0, 1],
    { representative: Some(0), start: 0, end: 2, },
    AggregateInputExpression(lowered("\"1 / 0\"")),
    Some(lowered("\"FALSE\"")),
    0,
    { remaining: 1000, max_frames: 100, },
    workspace,
    Some(expression_roots(logical, 100)),
  )
  let mut completed = false
  for _ in 0..<40 {
    if !completed {
      match advance_aggregate_contributors(state).unwrap() {
        None => ()
        Some((sources, values)) => {
          assert_eq(sources.length(), 0)
          assert_eq(values.length(), 0)
          completed = true
        }
      }
    }
  }
  assert_true(completed)
  assert_eq(workspace.live, 0)
  assert_eq(logical.live, 0L)
}

///|
test "stepped aggregate cancellation reclaims earlier contributors" {
  let input = row_capture(row_owner(""))
  let workspace = row_workspace(100)
  assert_true(reserve_slots(workspace, 3))
  let logical = test_logical_budget(1000L, 1000L)
  let control : ControlBudget = { remaining: 1000, max_frames: 100, }
  let state = start_aggregate_contributors(
    input,
    ["a", "b"],
    [0, 1],
    { representative: Some(0), start: 0, end: 2, },
    AggregateInputExpression(lowered("\"7\"")),
    None,
    0,
    control,
    workspace,
    Some(expression_roots(logical, 100)),
  )
  for _ in 0..<20 {
    if state.values.is_empty() {
      assert_true(advance_aggregate_contributors(state) is Ok(None))
    }
  }
  assert_eq(state.values.length(), 1)
  assert_true(advance_aggregate_contributors(state) is Ok(None))
  assert_true(advance_aggregate_contributors(state) is Ok(None))
  let remaining = control.remaining
  let work = logical.work
  close_aggregate_contributors(state)
  close_aggregate_contributors(state)
  assert_eq(state.values.length(), 0)
  assert_eq(state.sources.length(), 0)
  assert_eq(workspace.live, 3)
  assert_eq(logical.live, 0L)
  assert_eq(control.remaining, remaining)
  assert_eq(logical.work, work)
}
