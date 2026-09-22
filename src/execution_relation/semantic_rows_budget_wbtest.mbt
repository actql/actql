///|
test "vector comparison charges every compared dimension before traversal" {
  guard runtime_vector([1.0, 2.0, 3.0]) is Captured(left) else {
    fail("left vector")
  }
  guard runtime_vector([1.0, 2.0, 3.0]) is Captured(right) else {
    fail("right vector")
  }
  let exact = { remaining: 4, max_frames: 1, }
  assert_true(compare_admitted_value(left, right, exact) is Ok(0))
  assert_eq(exact.remaining, 0)

  let short = { remaining: 3, max_frames: 1, }
  assert_true(compare_admitted_value(left, right, short) is Err(Limit))
  // The outer value comparison is charged, but the all-or-nothing vector
  // dimension charge is rejected before traversal.
  assert_eq(short.remaining, 2)
}

///|
test "plain Text admission charges UTF-8 work before normalization" {
  let value = Text("é日😀")
  let exact = { remaining: 9, max_frames: 1, }
  assert_true(admitted_nest_value(value, exact) is Ok(@admitted.Text(_)))
  assert_eq(exact.remaining, 0)

  let short = { remaining: 8, max_frames: 1, }
  assert_true(admitted_nest_value(value, short) is Err(RowLimit))
  assert_eq(short.remaining, 8)

  let aggregate = { remaining: 9, max_frames: 1, }
  assert_true(
    admitted_aggregate_item(value, aggregate) is Ok(Some(@admitted.Text(_))),
  )
  assert_eq(aggregate.remaining, 0)
}

///|
test "timestamp work exhaustion remains a canonical resource error" {
  assert_true(window_time_row_issue(WindowTimeResourceLimit, 7) is RowLimit)
  assert_true(window_time_row_issue(InvalidWindowTime, 7) is WindowTime(7))
}
