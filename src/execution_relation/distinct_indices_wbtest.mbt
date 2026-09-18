///|
test "distinct index restores first occurrence order and treats nulls as equal" {
  let table = order_table([Number(2), Null, Number(1), Number(2), Null])
  assert_eq(
    distinct_indices(table, [0], { remaining: 10000, max_frames: 0, }, {
      limit: 100,
      live: 0,
      peak: 0,
    }).unwrap(),
    [0, 1, 2],
  )
  // Including the distinct payload makes every complete row unique.
  assert_eq(
    distinct_indices(table, [0, 1], { remaining: 10000, max_frames: 0, }, {
      limit: 100,
      live: 0,
      peak: 0,
    }).unwrap(),
    [0, 1, 2, 3, 4],
  )
  assert_true(table.rows[0][0] is Number(2))
}

///|
test "distinct scalar keys ignore structured payload and share exact comparison" {
  let payload = admitted_scalar(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
    "[1]",
  )
  let table = order_table([
    decimal_value("1.010", 3),
    decimal_value("0.999", 3),
    decimal_value("1.01", 2),
  ])
  for row in table.rows {
    row[1] = payload
  }
  assert_eq(
    distinct_indices(table, [0], { remaining: 10000, max_frames: 0, }, {
      limit: 100,
      live: 0,
      peak: 0,
    }).unwrap(),
    [0, 1],
  )
}

///|
test "distinct workspace and work boundaries cleanly fail and permit reuse" {
  let table = order_table([Text("é"), Text("a"), Text("é")])
  let workspace = { limit: 100, live: 5, peak: 5, }
  let control = { remaining: 10000, max_frames: 0, }
  assert_eq(distinct_indices(table, [0], control, workspace).unwrap(), [0, 1])
  assert_eq(workspace.live, 7)
  let used = 10000 - control.remaining
  let peak = workspace.peak
  for
    (work, space, success) in [
      (used, peak, true),
      (used - 1, peak, false),
      (used, peak - 1, false),
    ] {
    let workspace = { limit: space, live: 5, peak: 5, }
    let result = distinct_indices(
      table,
      [0],
      { remaining: work, max_frames: 0, },
      workspace,
    )
    if success {
      assert_eq(result.unwrap(), [0, 1])
      assert_eq(workspace.live, 7)
    } else {
      assert_true(result is Err(Limit))
      assert_eq(workspace.live, 5)
    }
  }
}

///|
test "distinct empty rows zero column tuples and invalid ordinals" {
  for
    (table, expected) in [
      (order_table([]), []),
      (order_table([Null, Null]), [0]),
    ] {
    assert_eq(
      distinct_indices(table, [], { remaining: 100, max_frames: 0, }, {
        limit: 100,
        live: 0,
        peak: 0,
      }).unwrap(),
      expected,
    )
  }
  let workspace = { limit: 100, live: 7, peak: 7, }
  assert_true(
    distinct_indices(
      order_table([]),
      [2],
      { remaining: 100, max_frames: 0, },
      workspace,
    )
    is Err(InvalidInput),
  )
  assert_eq(workspace.live, 7)
}

///|
test "distinct work is subquadratic for all equal and all different rows" {
  for count in [100, 1000, 10000] {
    for same in [true, false] {
      let table = order_table(
        Array::makei(count, i => {
          Number(if same { 1.0 } else { (count - i).to_double() })
        }),
      )
      let control = { remaining: 10000000, max_frames: 0, }
      let workspace = { limit: count * 3 + 2, live: 0, peak: 0, }
      let result = distinct_indices(table, [0], control, workspace).unwrap()
      assert_eq(result.length(), if same { 1 } else { count })
      for i = 0; i < result.length(); i = i + 1 {
        assert_eq(result[i], i)
      }
      assert_eq(workspace.live, result.length())
      assert_true(10000000 - control.remaining < count * 45)
    }
  }
}

///|
test "distinct work and workspace bounds are exact at scale" {
  let count = 1000
  let input = order_table(Array::makei(count, i => Number(i.to_double())))
  let maximum = 1000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: maximum, live: 0, peak: 0, }
  assert_eq(
    distinct_indices(input, [0], control, workspace).unwrap().length(),
    count,
  )
  let used = maximum - control.remaining
  let peak = workspace.peak
  for (work, space, success) in [
    (used, peak, true),
    (used - 1, peak, false),
    (used, peak - 1, false),
  ] {
    let result = distinct_indices(
      input,
      [0],
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
