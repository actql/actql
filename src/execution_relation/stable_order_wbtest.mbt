///|
fn order_table(values : Array[Value]) -> Table {
  {
    owner: row_owner(""),
    id: "fixture",
    names: ["key", "payload"],
    rows: values.mapi((i, v) => [v, Number(i.to_double())]),
  }
}

///|
test "stepped stable order preserves exact work and workspace boundaries" {
  // Two numeric rows: one term, two row checks, four initialized indices,
  // two merge writes, and one comparison term total ten units.
  for (work, space, success) in [(10, 5, true), (9, 5, false), (10, 4, false)] {
    let workspace = row_workspace(space)
    let control : ControlBudget = { remaining: work, max_frames: 10, }
    let state = start_stable_order(
      order_table([Number(2), Number(1)]),
      [{ column: 0, descending: false, nulls_first: false, }],
      control,
      workspace,
    )
    let mut terminal = false
    for _ in 0..<100 {
      if !terminal {
        match advance_stable_order(state) {
          Ok(None) => ()
          Ok(Some(indices)) => {
            assert_true(success)
            assert_eq(indices, [1, 0])
            assert_eq(workspace.live, 2)
            assert_eq(control.remaining, 0)
            terminal = true
          }
          Err(Limit) => {
            assert_false(success)
            assert_eq(workspace.live, 0)
            terminal = true
          }
          Err(_) => fail("unexpected ordering failure")
        }
      }
    }
    assert_true(terminal)
  }
}

///|
test "stepped stable order can abandon a long common prefix comparison" {
  let prefix = "a".repeat(4096)
  let workspace = row_workspace(8)
  assert_true(reserve_slots(workspace, 3))
  let control : ControlBudget = { remaining: 30000, max_frames: 10, }
  let state = start_stable_order(
    order_table([Text(prefix + "b"), Text(prefix + "a")]),
    [{ column: 0, descending: false, nulls_first: false, }],
    control,
    workspace,
  )
  let mut reached = false
  for _ in 0..<20000 {
    if !reached {
      assert_true(advance_stable_order(state) is Ok(None))
      reached = state.comparison.phase == 3 && state.comparison.offset == 8
    }
  }
  assert_true(reached)
  let remaining = control.remaining
  close_stable_order(state)
  close_stable_order(state)
  assert_eq(control.remaining, remaining)
  assert_eq(workspace.live, 3)
  assert_eq(state.source.length(), 0)
  assert_eq(state.target.length(), 0)
  assert_true(advance_stable_order(state) is Err(InvalidInput))
}

///|
test "stable ordering reuses exact decimal and UTF16 scalar comparisons" {
  for
    (table, expected) in [
      (
        order_table([
          decimal_value("1.01", 2),
          decimal_value("0.999", 3),
          decimal_value("1.001", 3),
          decimal_value("1.010", 3),
        ]),
        [1, 2, 0, 3],
      ),
      (order_table([Text("\u{e000}"), Text("\u{10000}"), Text("a")]), [2, 1, 0]),
    ] {
    assert_eq(
      stable_order_indices(
        table,
        [{ column: 0, descending: false, nulls_first: false, }],
        { remaining: 10000, max_frames: 0, },
        { limit: 100, live: 0, peak: 0, },
      ).unwrap(),
      expected,
    )
  }
}

///|
test "invalid ordinal is rejected on empty input and comparison failures release scratch" {
  let workspace = { limit: 100, live: 7, peak: 7, }
  assert_true(
    stable_order_indices(
      order_table([]),
      [{ column: 2, descending: false, nulls_first: false, }],
      { remaining: 100, max_frames: 0, },
      workspace,
    )
    is Err(InvalidInput),
  )
  assert_eq(workspace.live, 7)
  let structured = admitted_scalar(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
    "[1]",
  )
  assert_true(
    stable_order_indices(
      order_table([structured, structured]),
      [{ column: 0, descending: false, nulls_first: false, }],
      { remaining: 100, max_frames: 0, },
      workspace,
    )
    is Err(Scalar(ComparisonDomainNotImplemented)),
  )
  assert_eq(workspace.live, 7)
}

///|
test "stable index ordering keeps equal inputs and separates direction from null placement" {
  let table = order_table([Number(2), Null, Number(1), Number(2), Null])
  for
    (descending, first, expected) in [
      (false, false, [2, 0, 3, 1, 4]),
      (true, false, [0, 3, 2, 1, 4]),
      (false, true, [1, 4, 2, 0, 3]),
      (true, true, [1, 4, 0, 3, 2]),
    ] {
    let workspace = { limit: 11, live: 0, peak: 0, }
    let indices = stable_order_indices(
      table,
      [{ column: 0, descending, nulls_first: first, }],
      { remaining: 10000, max_frames: 0, },
      workspace,
    ).unwrap()
    assert_eq(indices, expected)
    assert_eq(workspace.live, 5)
    assert_eq(workspace.peak, 11)
    assert_true(table.rows[0][0] is Number(2))
  }
  assert_eq(
    stable_order_indices(table, [], { remaining: 100, max_frames: 0, }, {
      limit: 5,
      live: 0,
      peak: 0,
    }).unwrap(),
    [0, 1, 2, 3, 4],
  )
}

///|
test "ordering budgets have exact boundaries and release only owned workspace on failure" {
  let table = order_table([Text("é"), Text("a"), Text("é")])
  let order = [{ column: 0, descending: false, nulls_first: false, }]
  let budget = { remaining: 10000, max_frames: 0, }
  let result = stable_order_indices(table, order, budget, {
    limit: 12,
    live: 5,
    peak: 5,
  }).unwrap()
  assert_eq(result, [1, 0, 2])
  let used = 10000 - budget.remaining
  assert_true(
    stable_order_indices(table, order, { remaining: used, max_frames: 0, }, {
      limit: 12,
      live: 5,
      peak: 5,
    })
    is Ok(_),
  )
  let workspace = { limit: 12, live: 5, peak: 5, }
  let short = { remaining: used - 1, max_frames: 0, }
  assert_true(
    stable_order_indices(table, order, short, workspace) is Err(Limit),
  )
  assert_eq(workspace.live, 5)
  assert_true(short.remaining < used - 1)
  assert_true(
    stable_order_indices(table, order, { remaining: 10000, max_frames: 0, }, {
      limit: 11,
      live: 5,
      peak: 5,
    })
    is Err(Limit),
  )
}

///|
test "stable merge work grows logarithmically rather than quadratically" {
  for count in [100, 1000, 10000] {
    for same in [true, false] {
      let table = order_table(
        Array::makei(count, i => {
          Number(if same { 1.0 } else { (count - i).to_double() })
        }),
      )
      let budget = { remaining: 10000000, max_frames: 0, }
      let workspace = { limit: count * 2 + 1, live: 0, peak: 0, }
      let result = stable_order_indices(
        table,
        [{ column: 0, descending: false, nulls_first: false, }],
        budget,
        workspace,
      ).unwrap()
      for i = 0; i < count; i = i + 1 {
        assert_eq(result[i], if same { i } else { count - i - 1 })
      }
      assert_true(10000000 - budget.remaining < count * 35)
      assert_eq(workspace.peak, count * 2 + 1)
      assert_eq(workspace.live, count)
    }
  }
}

///|
test "stable ordering work and workspace bounds are exact at scale" {
  let count = 1000
  let table = order_table(
    Array::makei(count, i => Number((count - i).to_double())),
  )
  let order = [{ column: 0, descending: false, nulls_first: false, }]
  let maximum = 1000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: maximum, live: 0, peak: 0, }
  assert_eq(
    stable_order_indices(table, order, control, workspace).unwrap().length(),
    count,
  )
  let used = maximum - control.remaining
  let peak = workspace.peak
  for
    (work, space, success) in [
      (used, peak, true),
      (used - 1, peak, false),
      (used, peak - 1, false),
    ] {
    let result = stable_order_indices(
      table,
      order,
      { remaining: work, max_frames: 100, },
      { limit: space, live: 0, peak: 0, },
    )
    if success {
      assert_eq(result.unwrap().length(), count)
    } else {
      assert_true(result is Err(Limit))
    }
  }
}

///|
test "stable merge preparation charges at most one unit per advance" {
  let table = order_table(
    Array::makei(64, index => Number((64 - index).to_double())),
  )
  let control : ControlBudget = { remaining: 10000, max_frames: 0, }
  let workspace = { limit: 129, live: 0, peak: 0, }
  let state = start_stable_order(
    table,
    [{ column: 0, descending: false, nulls_first: false, }],
    control,
    workspace,
  )
  let mut result = None
  for _ in 0..<2000 {
    if result is None {
      let before = control.remaining
      result = advance_stable_order(state).unwrap()
      assert_true(before - control.remaining <= 1)
    }
  }
  assert_eq(result.unwrap()[0], 63)
  assert_eq(workspace.peak, 129)
  assert_eq(workspace.live, 64)
}

///|
test "stable merge charges supplementary text one byte per advance" {
  let table = order_table([
    Text("𠮷b"),
    Text("𠮷a"),
    Text("a"),
    Text("𠮷a"),
  ])
  let control : ControlBudget = { remaining: 10000, max_frames: 0, }
  let workspace = { limit: 9, live: 0, peak: 0, }
  let state = start_stable_order(
    table,
    [{ column: 0, descending: false, nulls_first: false, }],
    control,
    workspace,
  )
  let mut result = None
  for _ in 0..<1000 {
    if result is None {
      let before = control.remaining
      result = advance_stable_order(state).unwrap()
      assert_true(before - control.remaining <= 1)
    }
  }
  assert_eq(result.unwrap(), [2, 1, 3, 0])
  assert_eq(workspace.live, 4)
}

///|
test "stable merge charges decimal coefficients one byte per advance" {
  let table = order_table([
    decimal_value("99999999999999999999999999999999999999", 0),
    decimal_value("99999999999999999999999999999999999998", 0),
  ])
  let control : ControlBudget = { remaining: 1000, max_frames: 0, }
  let workspace = { limit: 5, live: 0, peak: 0, }
  let state = start_stable_order(
    table,
    [{ column: 0, descending: false, nulls_first: false, }],
    control,
    workspace,
  )
  let mut result = None
  for _ in 0..<400 {
    if result is None {
      let before = control.remaining
      result = advance_stable_order(state).unwrap()
      assert_true(before - control.remaining <= 1)
    }
  }
  assert_eq(result.unwrap(), [1, 0])
  assert_eq(workspace.live, 2)
}
