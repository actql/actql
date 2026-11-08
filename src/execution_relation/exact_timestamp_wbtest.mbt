///|
test "exact UTC scalar and complete comparisons retain nanosecond order" {
  let contract = "{\"type\":\"timestamp\",\"nullable\":false}"
  let a = admitted_scalar(contract, "\"1970-01-01T00:00:00.123Z\"")
  let b = admitted_scalar(contract, "\"1970-01-01T00:00:00.123000001Z\"")
  assert_eq(compare(a, b), Ok(-1))
  assert_eq(compare(b, a), Ok(1))
  assert_eq(compare(a, a), Ok(0))
  assert_eq(
    compare_complete_value(a, b, { remaining: 100, max_frames: 10, }).unwrap(),
    -1,
  )
  guard a is Captured(av) && b is Captured(bv) else {
    fail("admitted timestamps")
  }
  let control = { remaining: 100, max_frames: 10, }
  let workspace : RowWorkspace = row_workspace(20)
  let cursor = start_complete_tree_comparison(av, bv, control, workspace).unwrap()
  let mut order = None
  for _ in 0..<200 {
    if order is None {
      order = advance_complete_tree_comparison(cursor, control).unwrap()
    }
  }
  assert_eq(order, Some(-1))
  assert_eq(workspace.live, 0)
}

///|
test "ordinary row windows retain exact UTC nanoseconds at negative and end boundaries" {
  let table = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"timestamp\",\"nullable\":false}},\"rows\":[{\"at\":\"1969-12-31T23:59:59.999999999Z\"},{\"at\":\"1970-01-01T00:00:00.000Z\"},{\"at\":\"1970-01-01T00:00:00.000999999Z\"},{\"at\":\"1970-01-01T00:00:00.001Z\"}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1}}]",
    "window_1",
    max_rows=4,
  )
  assert_eq(table.rows.length(), 4)
  for
    (index, start, end) in [
      (0, -1.0, 0.0),
      (1, 0.0, 1.0),
      (2, 0.0, 1.0),
      (3, 1.0, 2.0),
    ] {
    assert_true(table.rows[index][1] is Number(actual) && actual == end)
    assert_true(table.rows[index][2] is Number(actual) && actual == start)
  }
  assert_true(
    table.rows[0][0]
    is Captured(@admitted.Timestamp("1969-12-31T23:59:59.999999999Z")),
  )
}

///|
test "unfinished millisecond interval and prefix consumers refuse finer UTC without rounding" {
  let value = admitted_scalar(
    "{\"type\":\"timestamp\",\"nullable\":false}", "\"1969-12-31T23:59:59.999999999Z\"",
  )
  assert_true(
    interval_clock(value, true, { remaining: 100, max_frames: 10, })
    is Err(TemporalPrecisionUnavailable),
  )
  assert_true(
    window_time_milliseconds(value, true, { remaining: 100, max_frames: 10, })
    is Err(WindowTimePrecisionUnavailable),
  )
}
