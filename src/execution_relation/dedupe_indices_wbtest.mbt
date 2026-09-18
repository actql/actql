///|
test "dedupe groups use canonical tuple identities not scalar key order" {
  let table = order_table([Number(2), Number(1), Number(2), Number(1)])
  let by = [{ column: 0, descending: false, nulls_first: false, }]
  let order = [{ column: 1, descending: true, nulls_first: false, }]
  // SHA256('[2]') = 0389... < SHA256('[1]') = 080a..., independently fixed.
  assert_eq(
    dedupe_indices(table, by, order, { remaining: 100000, max_frames: 0, }, {
      limit: 1000,
      live: 0,
      peak: 0,
    }).unwrap(),
    [2, 3],
  )
  assert_eq(
    dedupe_key_identity(table, 0, by, { remaining: 1000, max_frames: 0, }).unwrap(),
    "038966de9f6b9a901b20b4c6ca8b2a46009feebe031babc842d43690c0bc222b",
  )
  assert_eq(
    dedupe_key_identity(table, 1, [by[0], by[0]], {
      remaining: 1000,
      max_frames: 0,
    }).unwrap(),
    "e61b9f584dbe27741cef6e9ee440831d7d94470c0871b0871541f0308916efea",
  )
}

///|
test "dedupe global partition empty input and lower-ranked ties" {
  let table = order_table([Number(2), Number(1), Number(1)])
  let order = [{ column: 0, descending: true, nulls_first: false, }]
  assert_eq(
    dedupe_indices(table, [], order, { remaining: 10000, max_frames: 0, }, {
      limit: 1000,
      live: 0,
      peak: 0,
    }).unwrap(),
    [0],
  )
  assert_eq(
    dedupe_indices(
      order_table([]),
      [],
      order,
      { remaining: 10000, max_frames: 0, },
      { limit: 1000, live: 0, peak: 0, },
    ).unwrap(),
    [],
  )
  assert_true(
    dedupe_indices(table, [], [], { remaining: 10000, max_frames: 0, }, {
      limit: 1000,
      live: 0,
      peak: 0,
    })
    is Err(Ordering(InvalidInput)),
  )
}

///|
test "dedupe top tie fails before any survivor escapes and resets only local scratch" {
  let table = order_table([Number(1), Number(1), Number(2), Number(2)])
  let by = [{ column: 0, descending: false, nulls_first: false, }]
  // Authored order ties in both groups. CID order makes group 2 fail first.
  let workspace = { limit: 1000, live: 7, peak: 7, }
  assert_true(
    dedupe_indices(
      table,
      by,
      by,
      { remaining: 100000, max_frames: 0, },
      workspace,
    )
    is Err(TopTie(2, 3)),
  )
  assert_eq(workspace.live, 7)
  assert_eq(
    dedupe_indices(
      table,
      by,
      [{ column: 1, descending: true, nulls_first: false, }],
      { remaining: 100000, max_frames: 0, },
      workspace,
    ).unwrap(),
    [3, 1],
  )
  assert_eq(workspace.live, 9)
}

///|
test "dedupe budget exactness includes canonical identity and final group sorting" {
  let table = order_table([Null, Number(1), Null, Number(1)])
  let by = [{ column: 0, descending: false, nulls_first: false, }]
  let order = [{ column: 1, descending: true, nulls_first: false, }]
  let control = { remaining: 100000, max_frames: 0, }
  let workspace = { limit: 1000, live: 5, peak: 5, }
  assert_eq(dedupe_indices(table, by, order, control, workspace).unwrap(), [
    3, 2,
  ])
  let used = 100000 - control.remaining
  let peak = workspace.peak
  for
    (work, entries, good) in [
      (used, peak, true),
      (used - 1, peak, false),
      (used, peak - 1, false),
    ] {
    let workspace = { limit: entries, live: 5, peak: 5, }
    let result = dedupe_indices(
      table,
      by,
      order,
      { remaining: work, max_frames: 0, },
      workspace,
    )
    if good {
      assert_eq(result.unwrap(), [3, 2])
      assert_eq(workspace.live, 7)
    } else {
      assert_true(result is Err(Ordering(Limit)))
      assert_eq(workspace.live, 5)
    }
  }
}

///|
test "dedupe grouping remains bounded for equal and different keys at scale" {
  for count in [100, 1000, 10000] {
    for same in [true, false] {
      let table = order_table(
        Array::makei(count, i => Number(if same { 1.0 } else { i.to_double() })),
      )
      let control = { remaining: 100000000, max_frames: 0, }
      let workspace = { limit: count * 80 + 10, live: 0, peak: 0, }
      let result = dedupe_indices(
        table,
        [{ column: 0, descending: false, nulls_first: false, }],
        [{ column: 1, descending: true, nulls_first: false, }],
        control,
        workspace,
      ).unwrap()
      assert_eq(result.length(), if same { 1 } else { count })
      if same {
        assert_eq(result[0], count - 1)
      } else {
        let seen = Array::make(count, false)
        for index in result {
          assert_false(seen[index])
          seen[index] = true
        }
        for present in seen {
          assert_true(present)
        }
      }
      assert_eq(workspace.live, result.length())
      assert_true(100000000 - control.remaining < count * 5000)
    }
  }
}

///|
test "dedupe large indexed budgets are exact and fail atomically" {
  let count = 1000
  let table = order_table(
    Array::makei(count, i => Number((i % 100).to_double())),
  )
  let by = [{ column: 0, descending: false, nulls_first: false, }]
  let order = [{ column: 1, descending: true, nulls_first: false, }]
  let maximum = 10000000
  let control = { remaining: maximum, max_frames: 0, }
  let workspace = { limit: maximum, live: 7, peak: 7, }
  let expected = dedupe_indices(table, by, order, control, workspace).unwrap()
  assert_eq(expected.length(), 100)
  let used = maximum - control.remaining
  let peak = workspace.peak
  for
    (work, entries, good) in [
      (used, peak, true),
      (used - 1, peak, false),
      (used, peak - 1, false),
    ] {
    let attempt = { limit: entries, live: 7, peak: 7, }
    let result = dedupe_indices(
      table,
      by,
      order,
      { remaining: work, max_frames: 0, },
      attempt,
    )
    if good {
      assert_eq(result.unwrap(), expected)
      assert_eq(attempt.live, 7 + expected.length())
    } else {
      assert_true(result is Err(Ordering(Limit)))
      assert_eq(attempt.live, 7)
    }
  }
}
