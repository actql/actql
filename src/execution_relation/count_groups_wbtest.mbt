///|
test "count groups reuse exact decimal equality and stable representatives" {
  let table = order_table([
    decimal_value("1.01", 2),
    Null,
    decimal_value("0.999", 3),
    decimal_value("1.010", 3),
    Null,
  ])
  let workspace = { limit: 100, live: 3, peak: 3, }
  let groups = count_groups(
    table,
    [{ column: 0, descending: false, nulls_first: true, }],
    [None, Some(0)],
    3,
    { remaining: 10000, max_frames: 0, },
    workspace,
  ).unwrap()
  assert_eq(groups.map(g => g.representative), [Some(1), Some(2), Some(0)])
  assert_eq(groups.map(g => g.counts), [[2, 0], [1, 1], [2, 2]])
  assert_eq(workspace.live, 12)
}

///|
test "count groups distinguish empty global aggregation from empty keyed input" {
  let table = order_table([])
  let run = fn(order, counts) {
    count_groups(table, order, counts, 1, { remaining: 1000, max_frames: 0, }, {
      limit: 100,
      live: 0,
      peak: 0,
    }).unwrap()
  }
  let global = run([], [None, Some(0)])
  assert_eq(global.length(), 1)
  assert_eq(global[0].representative, None)
  assert_eq(global[0].counts, [0, 0])
  assert_eq(run([], [])[0].counts, [])
  assert_eq(
    run([{ column: 0, descending: false, nulls_first: true, }], [None]).length(),
    0,
  )
}

///|
test "count groups enforce result and scratch limits without refunding work" {
  let table = order_table([Number(2), Number(1), Number(2)])
  let order = [{ column: 0, descending: false, nulls_first: true, }]
  for (max_groups, slots) in [(1, 100), (2, 4)] {
    let workspace = { limit: slots, live: 2, peak: 2, }
    let control = { remaining: 1000, max_frames: 0, }
    assert_true(
      count_groups(table, order, [None], max_groups, control, workspace)
      is Err(Limit),
    )
    assert_eq(workspace.live, 2)
    assert_true(control.remaining < 1000)
  }
  assert_true(
    count_groups(
      order_table([]),
      [],
      [Some(2)],
      1,
      { remaining: 1000, max_frames: 0, },
      { limit: 100, live: 0, peak: 0, },
    )
    is Err(InvalidInput),
  )
}

///|
test "count groups keep UTF16 ordering and compare typed columns without row materialization" {
  let order = [{ column: 0, descending: false, nulls_first: true, }]
  let strings = count_groups(
    order_table([Text("\u{e000}"), Text("\u{10000}"), Text("a"), Text("a")]),
    order,
    [None],
    3,
    { remaining: 10000, max_frames: 0, },
    { limit: 100, live: 0, peak: 0, },
  ).unwrap()
  assert_eq(strings.map(g => g.representative), [Some(2), Some(1), Some(0)])
  assert_eq(strings.map(g => g.counts), [[2], [1], [1]])
  let owner = row_owner("")
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let mut expected_work : Int? = None
  let mut expected_peak : Int? = None
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let input = layout_relation(captured, candidate)
    let workspace = { limit: 1000, live: 0, peak: 0, }
    let control = { remaining: 10000, max_frames: 0, }
    let groups = count_groups(
      input,
      order,
      [None, Some(1)],
      2,
      control,
      workspace,
    ).unwrap()
    assert_eq(groups.map(g => g.representative), [Some(1), Some(0)])
    assert_eq(groups.map(g => g.counts), [[1, 1], [1, 1]])
    match expected_work {
      None => expected_work = Some(control.remaining)
      Some(value) => assert_eq(control.remaining, value)
    }
    match expected_peak {
      None => expected_peak = Some(workspace.peak)
      Some(value) => assert_eq(workspace.peak, value)
    }
  }
}
