///|
fn execute_window_group(source : String, max_rows~ : Int) -> Table raise {
  let owner = bound_pipeline(source)
  let completed = match
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["window_group_2"],
      { ..run_limits(), max_rows, },
      { remaining: 100000, max_frames: 100, },
    ) {
    Ok(value) => value
    Err(Rows(step, OwnerMismatch)) =>
      fail("window group owner " + step.to_string())
    Err(Rows(step, InputMismatch)) =>
      fail("window group input " + step.to_string())
    Err(Rows(step, InvalidRows)) =>
      fail("window group rows " + step.to_string())
    Err(Rows(step, RowLimit)) => fail("window group limit " + step.to_string())
    Err(Rows(step, Aggregation(_))) =>
      fail("window group aggregate " + step.to_string())
    Err(_) => fail("window group sequence")
  }
  test_row_store(completed).tables[2].unwrap().table
}

///|
test "fixed window groups order boundaries before nullable authored keys" {
  let table = execute_window_group(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false},\"k\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"at\":1,\"k\":null},{\"at\":2,\"k\":null},{\"at\":11,\"k\":1}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}},{\"window_group\":{\"by\":[\"k\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
    max_rows=3,
  )
  assert_eq(table.names, ["k", "n", "window_end", "window_start"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Null)
  assert_true(table.rows[0][1] is Number(2))
  assert_true(table.rows[0][2] is Number(10))
  assert_true(table.rows[0][3] is Number(0))
  assert_true(table.rows[1][0] is Number(1))
  assert_true(table.rows[1][1] is Number(1))
  assert_true(table.rows[1][2] is Number(20))
  assert_true(table.rows[1][3] is Number(10))
}

///|
test "sliding window groups aggregate each assigned occurrence" {
  let table = execute_window_group(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":5},{\"at\":7}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}},{\"window_group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
    max_rows=4,
  )
  assert_eq(table.names, ["n", "window_end", "window_start"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[0][1] is Number(6))
  assert_true(table.rows[0][2] is Number(-4))
  assert_true(table.rows[1][0] is Number(2))
  assert_true(table.rows[1][1] is Number(12))
  assert_true(table.rows[1][2] is Number(2))
}

///|
test "empty window input creates no synthetic window group" {
  let table = execute_window_group(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}},{\"window_group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
    max_rows=1,
  )
  assert_eq(table.names, ["n", "window_end", "window_start"])
  assert_eq(table.rows.length(), 0)
}
