///|
test "aggregate group ranges advance canonical text boundaries" {
  let table = order_table([Text("𠮷a"), Text("𠮷a"), Text("𠮷b")])
  let control : ControlBudget = { remaining: 1000, max_frames: 0, }
  let workspace = { limit: 2, live: 0, peak: 0, }
  let state = start_aggregate_group_ranges(
    table,
    [0, 1, 2],
    [{ column: 0, descending: false, nulls_first: false, }],
    2,
    control,
    workspace,
  )
  let mut ranges = None
  for _ in 0..<200 {
    if ranges is None {
      let before = control.remaining
      ranges = advance_aggregate_group_ranges(state).unwrap()
      assert_true(before - control.remaining <= 1)
    }
  }
  let result = ranges.unwrap()
  assert_eq(result.length(), 2)
  assert_eq((result[0].start, result[0].end), (0, 2))
  assert_eq((result[1].start, result[1].end), (2, 3))
  assert_eq(result[0].representative, Some(0))
  assert_eq(result[1].representative, Some(2))
  assert_eq(workspace.peak, 2)
  assert_eq(workspace.live, 2)
  release_slots(workspace, 2)
}

///|
test "aggregate range failure releases only its own partial groups" {
  let table = order_table([Number(1), Number(2)])
  let control : ControlBudget = { remaining: 100, max_frames: 0, }
  let workspace = { limit: 4, live: 3, peak: 3, }
  let state = start_aggregate_group_ranges(
    table,
    [0, 1],
    [{ column: 0, descending: false, nulls_first: false, }],
    2,
    control,
    workspace,
  )
  let mut failed = false
  for _ in 0..<40 {
    if !failed {
      match advance_aggregate_group_ranges(state) {
        Ok(None) => ()
        Err(RowLimit) => failed = true
        _ => fail("expected one-short range workspace")
      }
    }
  }
  assert_true(failed)
  assert_eq(workspace.live, 3)
  assert_true(control.remaining < 100)
  assert_true(table.rows[0][0] is Number(1))
}

///|
test "aggregate range cancellation and empty global group keep exact limits" {
  let empty = order_table([])
  for (work, space, succeeds) in [(1, 1, true), (0, 1, false), (1, 0, false)] {
    let state = start_aggregate_group_ranges(
      empty,
      [],
      [],
      1,
      { remaining: work, max_frames: 0, },
      { limit: space, live: 0, peak: 0, },
    )
    let result = advance_aggregate_group_ranges(state)
    if succeeds {
      assert_eq(result.unwrap().unwrap().length(), 1)
    } else {
      assert_true(result is Err(RowLimit))
    }
  }
  let control : ControlBudget = { remaining: 1000, max_frames: 0, }
  let workspace = { limit: 4, live: 1, peak: 1, }
  let state = start_aggregate_group_ranges(
    order_table([Text("𠮷"), Text("𠮷")]),
    [0, 1],
    [{ column: 0, descending: false, nulls_first: false, }],
    2,
    control,
    workspace,
  )
  for _ in 0..<5 {
    assert_true(advance_aggregate_group_ranges(state) is Ok(None))
  }
  let remaining = control.remaining
  close_aggregate_group_ranges(state)
  assert_eq(workspace.live, 1)
  assert_eq(control.remaining, remaining)
  assert_true(advance_aggregate_group_ranges(state) is Err(InvalidRows))
}
