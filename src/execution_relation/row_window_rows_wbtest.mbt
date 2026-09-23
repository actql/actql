///|
fn execute_window(
  source : String,
  retained : String,
  max_rows~ : Int,
) -> Table raise {
  let owner = bound_pipeline(source)
  let completed = match
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      [retained],
      { ..run_limits(), max_rows, },
      { remaining: 100000, max_frames: 100, },
    ) {
    Ok(value) => value
    Err(Rows(step, OwnerMismatch)) => fail("window owner " + step.to_string())
    Err(Rows(step, InputMismatch)) => fail("window input " + step.to_string())
    Err(Rows(step, InvalidRows)) => fail("window rows " + step.to_string())
    Err(Rows(step, RowLimit)) => fail("window limit " + step.to_string())
    Err(Rows(step, WindowTime(row))) =>
      fail("window time " + step.to_string() + ":" + row.to_string())
    Err(Rows(step, WindowArithmetic(row))) =>
      fail("window arithmetic " + step.to_string() + ":" + row.to_string())
    Err(_) => fail("window sequence")
  }
  test_row_store(completed).tables[1].unwrap().table
}

///|
test "fixed row windows use the signed epoch grid and retain occurrence order" {
  let table = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":-1,\"id\":1},{\"at\":2,\"id\":2},{\"at\":12,\"id\":3}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10,\"step\":3,\"offset\":2}}]",
    "window_1",
    max_rows=3,
  )
  assert_eq(table.names, ["at", "id", "window_end", "window_start"])
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][1] is Number(1))
  assert_true(table.rows[0][2] is Number(2))
  assert_true(table.rows[0][3] is Number(-8))
  assert_true(table.rows[1][1] is Number(2))
  assert_true(table.rows[1][2] is Number(12))
  assert_true(table.rows[1][3] is Number(2))
  assert_true(table.rows[2][1] is Number(3))
  assert_true(table.rows[2][2] is Number(22))
  assert_true(table.rows[2][3] is Number(12))
}

///|
test "sliding row windows emit each occurrence in ascending start order" {
  let table = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":5,\"id\":1},{\"at\":7,\"id\":2}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}}]",
    "window_1",
    max_rows=4,
  )
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][1] is Number(1))
  assert_true(table.rows[0][2] is Number(6))
  assert_true(table.rows[0][3] is Number(-4))
  assert_true(table.rows[1][1] is Number(1))
  assert_true(table.rows[1][2] is Number(12))
  assert_true(table.rows[1][3] is Number(2))
  assert_true(table.rows[2][1] is Number(2))
  assert_true(table.rows[2][2] is Number(12))
  assert_true(table.rows[2][3] is Number(2))
}

///|
test "sliding row windows retain gaps and reject expansion past the row limit" {
  let gap = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":4}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":3,\"step\":5}}]",
    "window_1",
    max_rows=1,
  )
  assert_eq(gap.rows.length(), 0)
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":5}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}}]",
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["window_1"],
      { ..run_limits(), max_rows: 1, },
      { remaining: 100000, max_frames: 100, },
    )
    is Err(Rows(1, RowLimit)),
  )
}

///|
test "timestamp row windows convert canonical UTC values to Unix milliseconds" {
  let table = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"timestamp\",\"nullable\":false}},\"rows\":[{\"at\":\"1969-12-31T23:59:59.999Z\"},{\"at\":\"1970-01-01T00:00:00.250Z\"}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1000,\"offset\":250}}]",
    "window_1",
    max_rows=2,
  )
  assert_true(table.rows[0][1] is Number(250))
  assert_true(table.rows[0][2] is Number(-750))
  assert_true(table.rows[1][1] is Number(1250))
  assert_true(table.rows[1][2] is Number(250))
}

///|
test "fixed row windows retain exact grids across large signed offsets" {
  let negative_offset = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":2}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":3,\"offset\":-9007199254740991}}]",
    "window_1",
    max_rows=1,
  )
  assert_eq(negative_offset.rows.length(), 1)
  assert_true(negative_offset.rows[0][1] is Number(5))
  assert_true(negative_offset.rows[0][2] is Number(2))

  let positive_offset = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":-2}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":3,\"offset\":9007199254740991}}]",
    "window_1",
    max_rows=1,
  )
  assert_eq(positive_offset.rows.length(), 1)
  assert_true(positive_offset.rows[0][1] is Number(1))
  assert_true(positive_offset.rows[0][2] is Number(-2))
}

///|
test "row windows preserve exact boundaries for fractional times" {
  let table = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":2.5},{\"at\":5},{\"at\":-1.5}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":3,\"offset\":2}}]",
    "window_1",
    max_rows=3,
  )
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][1] is Number(5))
  assert_true(table.rows[0][2] is Number(2))
  assert_true(table.rows[1][1] is Number(8))
  assert_true(table.rows[1][2] is Number(5))
  assert_true(table.rows[2][1] is Number(-1))
  assert_true(table.rows[2][2] is Number(-4))
}

///|
test "sliding row windows use exact large-offset overlap boundaries" {
  let table = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":5}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":-9007199254740991}}]",
    "window_1",
    max_rows=2,
  )
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][1] is Number(9))
  assert_true(table.rows[0][2] is Number(-1))
  assert_true(table.rows[1][1] is Number(15))
  assert_true(table.rows[1][2] is Number(5))
}

///|
test "row windows admit representable large boundaries and reject others" {
  let representable = execute_window(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":9007199254740991}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":9007199254740991}}]",
    "window_1",
    max_rows=1,
  )
  assert_eq(representable.rows.length(), 1)
  assert_true(representable.rows[0][1] is Number(18014398509481982.0))
  assert_true(representable.rows[0][2] is Number(9007199254740991.0))
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":9007199254740992}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":8,\"step\":1}}]",
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["window_1"],
      { ..run_limits(), max_rows: 8, },
      { remaining: 100000, max_frames: 100, },
    )
    is Err(Rows(1, WindowArithmetic(0))),
  )
}

///|
// Expectations are transcribed from the separately authored
// portability/corpus/event-window-boundaries.json.
test "row windows share the exact finite boundary vectors with Events" {
  for
    (time, size, expected_start, expected_end) in [
      ("-0.5", 10, -10.0, 0.0),
      ("0.5", 10, 0.0, 10.0),
      ("9007199254740992", 8, 9007199254740992.0, 9007199254741000.0),
      ("18014398509481984", 4, 18014398509481984.0, 18014398509481988.0),
      (
        "9223372036854775808", 2048, 9223372036854775808.0, 9223372036854777856.0,
      ),
      (
        "-9223372036854775808", 2048, -9223372036854775808.0, -9223372036854773760.0,
      ),
    ] {
    let source = "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":" +
      time +
      "}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":" +
      size.to_string() +
      "}}]"
    let table = execute_window(source, "window_1", max_rows=1)
    assert_eq(table.rows.length(), 1)
    assert_true(table.rows[0][1] is Number(end) && end == expected_end)
    assert_true(table.rows[0][2] is Number(start) && start == expected_start)
  }
}

///|
test "row windows enforce the exact shared execution work boundary" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\"," +
    "\"nullable\":false}},\"rows\":[{\"at\":5},{\"at\":7}]}," +
    "\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\"," +
    "\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}}]",
  )
  let sequence = prepared_sequence(owner)
  let maximum = 100000
  let control = { remaining: maximum, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["window_1"],
      { ..run_limits(), max_rows: 4, },
      control,
    )
    is Ok(_),
  )
  let used = maximum - control.remaining
  for (budget, succeeds) in [(used, true), (used - 1, false)] {
    let bounded = { remaining: budget, max_frames: 100, }
    assert_eq(
      evaluate_sequence_components(
        registered_relation_contracts(),
        sequence,
        [],
        ["window_1"],
        { ..run_limits(), max_rows: 4, },
        bounded,
      )
      is Ok(_),
      succeeds,
    )
  }
}
