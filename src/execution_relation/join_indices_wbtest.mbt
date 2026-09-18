///|
test "inner join indices preserve left major right minor duplicates and exact decimal equality" {
  let left = order_table([
    decimal_value("1.01", 2),
    Null,
    decimal_value("2.0", 1),
    decimal_value("1.010", 3),
  ])
  let right = order_table([
    decimal_value("2.00", 2),
    decimal_value("1.010", 3),
    Null,
    decimal_value("1.01", 2),
  ])
  let workspace = { limit: 1000, live: 3, peak: 3, }
  let pairs = inner_join_indices(
    left,
    right,
    [(0, 0), (0, 0)],
    false,
    5,
    { remaining: 10000, max_frames: 0, },
    workspace,
  ).unwrap()
  assert_eq(pairs, [(0, 1), (0, 3), (2, 0), (3, 1), (3, 3)])
  assert_eq(workspace.live, 13)
}

///|
test "inner join indices bound intermediate output and release only their own scratch" {
  let left = order_table([Number(1), Number(1)])
  let right = order_table([Number(1), Number(1)])
  for (rows, slots, work) in [(3, 100, 1000), (4, 5, 1000), (4, 100, 1)] {
    let workspace = { limit: slots, live: 2, peak: 2, }
    let control = { remaining: work, max_frames: 0, }
    assert_true(
      inner_join_indices(left, right, [(0, 0)], false, rows, control, workspace)
      is Err(Limit),
    )
    assert_eq(workspace.live, 2)
    assert_true(control.remaining < work)
  }
  let workspace = { limit: 100, live: 2, peak: 2, }
  assert_eq(
    inner_join_indices(
      left,
      order_table([]),
      [(0, 0)],
      false,
      0,
      { remaining: 1000, max_frames: 0, },
      workspace,
    ).unwrap(),
    [],
  )
  assert_eq(workspace.live, 2)
}

///|
test "null fail scans both join inputs even opposite an empty relation" {
  for left_null in [true, false] {
    let empty = order_table([])
    let nullable = order_table([Number(1), Null])
    let workspace = { limit: 100, live: 0, peak: 0, }
    let result = inner_join_indices(
      if left_null {
        nullable
      } else {
        empty
      },
      if left_null {
        empty
      } else {
        nullable
      },
      [(0, 0)],
      true,
      100,
      { remaining: 1000, max_frames: 0, },
      workspace,
    )
    guard result is Err(NullKey(left~, row~, key~)) else { abort("null key") }
    assert_eq((left, row, key), (left_null, 1, 0))
    assert_eq(workspace.live, 0)
  }
}

///|
test "inner join physical indices reject malformed coordinates and preserve input storage" {
  let table = order_table([Text("a"), Text("b"), Text("a")])
  for keys in [[], [(2, 0)], [(0, -1)]] {
    assert_true(
      inner_join_indices(
        table,
        table,
        keys,
        false,
        10,
        { remaining: 1000, max_frames: 0, },
        { limit: 100, live: 0, peak: 0, },
      )
      is Err(InvalidInput),
    )
  }
  let result = inner_join_indices(
    table,
    table,
    [(0, 0)],
    false,
    5,
    { remaining: 1000, max_frames: 0, },
    { limit: 100, live: 0, peak: 0, },
  ).unwrap()
  assert_eq(result, [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)])
  assert_true(IndexedRows::read_cell(table, 0, 0) is Text("a"))
}

///|
test "composite equality uses every ordered pair and never matches a null component" {
  let left = {
    ..order_table([]),
    rows: [[Number(1), Text("b")], [Number(1), Text("a")], [Number(1), Null]],
  }
  let right = {
    ..order_table([]),
    rows: [
      [Number(1), Text("a")],
      [Number(1), Text("b")],
      [Number(1), Text("a")],
      [Number(1), Null],
    ],
  }
  assert_eq(
    inner_join_indices(
      left,
      right,
      [(0, 0), (1, 1)],
      false,
      3,
      { remaining: 10000, max_frames: 0, },
      { limit: 100, live: 0, peak: 0, },
    ).unwrap(),
    [(0, 1), (1, 0), (1, 2)],
  )
  let right = {
    ..order_table([]),
    rows: [[Number(1), Number(2)], [Number(1), Number(1)]],
  }
  assert_eq(
    inner_join_indices(
      left,
      right,
      [(0, 0), (0, 1)],
      false,
      3,
      { remaining: 10000, max_frames: 0, },
      { limit: 100, live: 0, peak: 0, },
    ).unwrap(),
    [(0, 1), (1, 1), (2, 1)],
  )
}

///|
test "join indices accept independently selected layouts without row materialization" {
  let owner = row_owner("")
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let mut expected : (Int, Int)? = None
  for left_layout in [RowLayout, ValueColumns, TypedColumns] {
    for right_layout in [RowLayout, ValueColumns, TypedColumns] {
      let left = layout_relation(captured, left_layout)
      let right = layout_relation(captured, right_layout)
      let control = { remaining: 10000, max_frames: 0, }
      let workspace = { limit: 100, live: 0, peak: 0, }
      assert_eq(
        inner_join_indices(
          left,
          right,
          [(0, 0), (1, 1)],
          false,
          2,
          control,
          workspace,
        ).unwrap(),
        [(0, 0), (1, 1)],
      )
      assert_eq(workspace.live, 4)
      let usage = (control.remaining, workspace.peak)
      if expected is Some(value) {
        assert_eq(usage, value)
      } else {
        expected = Some(usage)
      }
    }
  }
}

///|
test "join key validation precedes output construction and preserves scalar diagnostics" {
  let workspace = { limit: 100, live: 2, peak: 2, }
  // An empty permitted output does not remove the obligation to inspect a
  // declared fail-on-NULL key, even on the right of an empty left input.
  assert_true(
    inner_join_indices(
      order_table([]),
      order_table([Null]),
      [(0, 0)],
      true,
      0,
      { remaining: 1000, max_frames: 0, },
      workspace,
    )
    is Err(NullKey(left=false, row=0, key=0)),
  )
  assert_eq(workspace.live, 2)
  // A malformed physical row is not silently interpreted as a NULL key.
  let malformed = { ..order_table([]), rows: [[Number(1)]], }
  assert_true(
    inner_join_indices(
      order_table([]),
      malformed,
      [(0, 0)],
      false,
      0,
      { remaining: 1000, max_frames: 0, },
      workspace,
    )
    is Err(InvalidInput),
  )
  assert_eq(workspace.live, 2)
  // The scalar layer, not a stringified/hash key, decides comparability.
  assert_true(
    inner_join_indices(
      order_table([Number(1)]),
      order_table([Text("1")]),
      [(0, 0)],
      false,
      1,
      { remaining: 1000, max_frames: 0, },
      workspace,
    )
    is Err(Scalar(InvalidOperand)),
  )
  assert_eq(workspace.live, 2)
}

///|
test "join uniqueness validates nonmatching keys and reports the first duplicate input row" {
  let table = order_table([Number(9), Number(9), Number(1), Number(1)])
  for left in [true, false] {
    let workspace = { limit: 100, live: 3, peak: 3, }
    assert_true(
      validate_join_unique_indices(
        table,
        [{ column: 0, descending: false, nulls_first: true, }],
        left,
        { remaining: 1000, max_frames: 0, },
        workspace,
      )
      is Err(DuplicateKey(left=side, row=1, previous=0)) &&
      side == left,
    )
    assert_eq(workspace.live, 3)
  }
}

///|
test "join cardinality comparison excludes null tuples and uses exact decimal equality" {
  let order = [{ column: 0, descending: false, nulls_first: true, }]
  let workspace = { limit: 100, live: 2, peak: 2, }
  assert_true(
    validate_join_unique_indices(
      order_table([Null, Number(1), Null]),
      order,
      true,
      { remaining: 1000, max_frames: 0, },
      workspace,
    )
    is Ok(_),
  )
  assert_true(
    validate_join_unique_indices(
      order_table([decimal_value("1.00", 2), Null, decimal_value("1.000", 3)]),
      order,
      false,
      { remaining: 1000, max_frames: 0, },
      workspace,
    )
    is Err(DuplicateKey(left=false, row=2, previous=0)),
  )
  assert_eq(workspace.live, 2)
  let control = { remaining: 1, max_frames: 0, }
  assert_true(
    validate_join_unique_indices(
      order_table([Number(1), Number(2)]),
      order,
      false,
      control,
      workspace,
    )
    is Err(Limit),
  )
  assert_eq(workspace.live, 2)
  assert_eq(control.remaining, 0)
}

///|
test "join indices accept every KeyComparable value domain" {
  let live = Ref(true)
  let resource_contract = select_checked_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let resource = capture(
    issued_resource_value(
      resource_contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      live,
    ).value,
  )
  let other_resource = capture(
    issued_resource_value(
      resource_contract, "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      live,
    ).value,
  )
  let artifact_contract = select_checked_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let artifact = capture(issued_artifact_value(artifact_contract, live).value)
  for
    (left, right, expected) in [
      ([Number(1), Number(2)], [Number(1)], 0),
      ([Boolean(false), Boolean(true)], [Boolean(true)], 1),
      ([Text("é"), Text("z")], [Text("é")], 0),
      (
        [
          admitted_scalar(
            "{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"",
          ),
          admitted_scalar(
            "{\"type\":\"date\",\"nullable\":false}", "\"2026-01-01\"",
          ),
        ],
        [
          admitted_scalar(
            "{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"",
          ),
        ],
        0,
      ),
      (
        [
          admitted_scalar(
            "{\"type\":\"timestamp\",\"nullable\":false}", "\"2026-01-01T23:59:59.999Z\"",
          ),
          admitted_scalar(
            "{\"type\":\"timestamp\",\"nullable\":false}", "\"2026-01-02T00:00:00.000Z\"",
          ),
        ],
        [
          admitted_scalar(
            "{\"type\":\"timestamp\",\"nullable\":false}", "\"2026-01-01T23:59:59.999Z\"",
          ),
        ],
        0,
      ),
      (
        [decimal_value("1.00", 2), decimal_value("2.0", 1)],
        [decimal_value("1", 0)],
        0,
      ),
      ([resource, other_resource], [resource], 0),
      ([artifact], [artifact], 0),
    ] {
    assert_eq(
      inner_join_indices(
        order_table(left),
        order_table(right),
        [(0, 0)],
        false,
        2,
        { remaining: 100000, max_frames: 0, },
        { limit: 1000, live: 0, peak: 0, },
      ).unwrap(),
      [(expected, 0)],
    )
  }
  live.val = false
}
