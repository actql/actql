///|
test "retention follows explicit branch references without pruning unconsumed operations" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 1\"},\"as\":\"augmented\"},{\"filter\":\"a > 10\"},{\"from\":\"augmented\",\"select\":[\"c\"]}",
  )
  let retained_ids = ["select_3"]
  let workspace = { limit: 23, live: 0, peak: 0, }
  let control = { remaining: 71, max_frames: 0, }
  let wiring = prepare_wiring(owner, retained_ids, control, workspace).unwrap()
  assert_eq(control.remaining, 0)
  assert_eq(workspace.peak, 23)
  assert_true(physical_equal(wiring.owner, owner))
  assert_eq(wiring.input_count, 0)
  assert_eq(wiring.ids, ["values_0", "derive_1", "where_2", "select_3"])
  assert_eq(wiring.routes, [[], [0], [1], [1]])
  assert_eq(wiring.last_use, [1, 3, 2, 3])
  assert_eq(wiring.retained, [false, false, false, true])
  // Four IDs, last-use entries, flags and routes; three route edges.
  assert_eq(workspace.live, 19)
  retained_ids[0] = "values_0"
  assert_eq(wiring.retained, [false, false, false, true])
  let all_discarded = prepare_wiring(
    owner,
    [],
    { remaining: 1000, max_frames: 0, },
    { limit: 1000, live: 0, peak: 0, },
  ).unwrap()
  assert_eq(all_discarded.routes.length(), 4)
  assert_eq(all_discarded.last_use, [1, 3, 2, 3])
  assert_true(
    prepare_wiring(owner, ["select_3"], { remaining: 70, max_frames: 0, }, {
      limit: 23,
      live: 0,
      peak: 0,
    })
    is Err(Limit),
  )
  assert_true(
    prepare_wiring(owner, ["select_3"], { remaining: 71, max_frames: 0, }, {
      limit: 22,
      live: 0,
      peak: 0,
    })
    is Err(Limit),
  )
}

///|
test "supplied input slot is distinct from a same-spelled authored step name" {
  let owner = input_owner()
  let wiring = prepare_wiring(
    owner,
    ["select_0", "select_0"],
    { remaining: 1000, max_frames: 0, },
    { limit: 1000, live: 0, peak: 0, },
  ).unwrap()
  assert_eq(wiring.input_count, 1)
  assert_eq(wiring.ids, ["input_0", "select_0"])
  assert_eq(wiring.routes, [[0]])
  assert_eq(wiring.last_use, [0, 0])
  assert_eq(wiring.retained, [false, true])
}

///|
test "retention preparation fails atomically on limits and foreign target IDs" {
  let owner = row_owner(",{\"select\":[\"a\"]}")
  assert_true(
    prepare_wiring(
      owner,
      ["not_in_owner"],
      { remaining: 1000, max_frames: 0, },
      { limit: 1000, live: 0, peak: 0, },
    )
    is Err(UnknownRetainedTarget("not_in_owner")),
  )
  assert_true(
    prepare_wiring(owner, [], { remaining: 0, max_frames: 0, }, {
      limit: 1000,
      live: 0,
      peak: 0,
    })
    is Err(Limit),
  )
  assert_true(
    prepare_wiring(owner, [], { remaining: 1000, max_frames: 0, }, {
      limit: 0,
      live: 0,
      peak: 0,
    })
    is Err(Limit),
  )
  assert_true(
    prepare_wiring(owner, [], { remaining: 1000, max_frames: 0, }, {
      limit: 1000,
      live: 1,
      peak: 1,
    })
    is Err(InvalidLimits),
  )
}
