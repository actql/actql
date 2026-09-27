///|
test "aggregate source snapshots and expressions advance independently" {
  let input = row_capture(row_owner(""))
  let control : ControlBudget = { remaining: 1000, max_frames: 100, }
  let workspace = row_workspace(100)
  let logical = test_logical_budget(1000L, 1000L)
  let state = start_aggregate_expression(
    lowered("\"1 + (2 + 3)\""),
    input,
    ["a", "b"],
    0,
    0,
    control,
    workspace,
    Some(expression_roots(logical, 100)),
  )
  assert_eq(control.remaining, 1000)
  assert_eq(workspace.live, 0)
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_eq(state.snapshot.length(), 0)
  assert_eq(control.remaining, 999)
  assert_eq(logical.work, 0L)
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_eq(state.snapshot.length(), 1)
  assert_eq(control.remaining, 998)
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_eq(state.snapshot.length(), 2)
  assert_eq(control.remaining, 996)
  let mut result = None
  let mut advances = 0
  while result is None && advances < 30 {
    result = advance_aggregate_expression(state).unwrap()
    advances += 1
  }
  assert_true(result is Some(Number(value)) && value == 6.0)
  assert_true(advances > 1)
  assert_true(state.closed)
  assert_eq(workspace.live, 0)
  assert_eq(logical.live, 0L)
  assert_true(advance_aggregate_expression(state) is Err(InvalidRows))
}

///|
test "aggregate expression cancellation preserves borrowed roots and charges" {
  for steps in [1, 2, 3, 4, 5] {
    let input = row_capture(row_owner(""))
    let control : ControlBudget = { remaining: 1000, max_frames: 100, }
    let workspace = row_workspace(100)
    let logical = test_logical_budget(1000L, 1000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let baseline = logical.live
    let state = start_aggregate_expression(
      lowered("\"1 + (2 + 3)\""),
      input,
      ["a", "b"],
      0,
      0,
      control,
      workspace,
      Some(expression_roots(logical, 100)),
    )
    for _ in 0..<steps {
      assert_true(advance_aggregate_expression(state) is Ok(None))
    }
    let remaining = control.remaining
    let charged = logical.work
    close_aggregate_expression(state)
    close_aggregate_expression(state)
    assert_eq(workspace.live, 0)
    assert_eq(logical.live, baseline)
    assert_eq(logical.work, charged)
    assert_eq(control.remaining, remaining)
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
  }
}

///|
test "aggregate expression failure releases its partial snapshot" {
  let input = row_capture(row_owner(""))
  let workspace = row_workspace(1)
  let logical = test_logical_budget(1000L, 1000L)
  let state = start_aggregate_expression(
    lowered("\"7\""),
    input,
    ["a", "b"],
    0,
    0,
    { remaining: 1000, max_frames: 100, },
    workspace,
    Some(expression_roots(logical, 100)),
  )
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_eq(workspace.live, 1)
  assert_true(advance_aggregate_expression(state) is Ok(None))
  assert_true(advance_aggregate_expression(state) is Err(RowLimit))
  assert_eq(workspace.live, 0)
  assert_eq(logical.live, 0L)
  assert_true(state.closed)
}

///|
test "aggregate snapshot charges long names one byte per advance" {
  let input = row_capture(row_owner(""))
  let control : ControlBudget = { remaining: 1000, max_frames: 100, }
  let workspace = row_workspace(100)
  let logical = test_logical_budget(1000L, 1000L)
  let state = start_aggregate_expression(
    lowered("\"7\""),
    input,
    ["𠮷𠮷", "b"],
    0,
    0,
    control,
    workspace,
    Some(expression_roots(logical, 100)),
  )
  let mut result = None
  for _ in 0..<80 {
    if result is None {
      let before = control.remaining
      result = advance_aggregate_expression(state).unwrap()
      assert_true(before - control.remaining <= 1)
    }
  }
  assert_true(result is Some(Number(value)) && value == 7.0)
  assert_eq(workspace.live, 0)
}
