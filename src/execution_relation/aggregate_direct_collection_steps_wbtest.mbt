///|
test "direct aggregate collection advances one contributor per step" {
  let table = order_table([Number(1), Null, Number(2)])
  let control : ControlBudget = { remaining: 3, max_frames: 0, }
  let workspace = { limit: 2, live: 0, peak: 0, }
  let state = start_aggregate_direct_collection(
    table,
    [0, 1, 2],
    { representative: Some(0), start: 0, end: 3, },
    Some(0),
    @relation.Sum,
    control,
    workspace,
  )
  for _ in 0..<3 {
    let before = control.remaining
    assert_true(advance_aggregate_direct_collection(state) is Ok(None))
    assert_eq(before - control.remaining, 1)
  }
  let (values, count) = advance_aggregate_direct_collection(state)
    .unwrap()
    .unwrap()
  assert_eq(values.length(), 2)
  assert_true(values[0] is Number(1))
  assert_true(values[1] is Number(2))
  assert_eq(count, 0)
  assert_eq(workspace.peak, 2)
  assert_eq(workspace.live, 2)
  release_slots(workspace, 2)
}

///|
test "direct aggregate collection preserves work and releases partial values" {
  let table = order_table([Number(1), Number(2)])
  for (work, space, exact) in [(2, 2, true), (1, 2, false), (2, 1, false)] {
    let control : ControlBudget = { remaining: work, max_frames: 0, }
    let workspace = { limit: space + 1, live: 1, peak: 1, }
    let state = start_aggregate_direct_collection(
      table,
      [0, 1],
      { representative: Some(0), start: 0, end: 2, },
      Some(0),
      @relation.Sum,
      control,
      workspace,
    )
    assert_true(advance_aggregate_direct_collection(state) is Ok(None))
    let second = advance_aggregate_direct_collection(state)
    if exact {
      assert_true(second is Ok(None))
      let (values, _) = advance_aggregate_direct_collection(state)
        .unwrap()
        .unwrap()
      assert_eq(values.length(), 2)
      release_slots(workspace, 2)
      assert_eq(workspace.live, 1)
    } else {
      assert_true(second is Err(RowLimit))
      assert_eq(workspace.live, 1)
      assert_eq(control.remaining, 0)
    }
  }
  let control : ControlBudget = { remaining: 2, max_frames: 0, }
  let workspace = { limit: 3, live: 1, peak: 1, }
  let state = start_aggregate_direct_collection(
    table,
    [0, 1],
    { representative: Some(0), start: 0, end: 2, },
    Some(0),
    @relation.Sum,
    control,
    workspace,
  )
  assert_true(advance_aggregate_direct_collection(state) is Ok(None))
  close_aggregate_direct_collection(state)
  assert_eq(workspace.live, 1)
  assert_eq(control.remaining, 1)
  assert_true(advance_aggregate_direct_collection(state) is Err(InvalidRows))
}
