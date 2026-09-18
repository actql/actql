///|
fn lag_scale_levels(count : Int) -> Int {
  let mut size = 1
  let mut levels = 0
  while size < count {
    size *= 2
    levels += 1
  }
  levels
}

///|
fn check_lag_scale(count : Int) -> Unit raise {
  let owner = lag_input_owner("1")
  let template = table_from_capture(
    capture_input(
      owner,
      0,
      [input_cursor("{\"group\":\"a\",\"id\":0,\"amount\":1}")],
      max_rows=1,
      run_limits().input_values,
    ).unwrap(),
  )
  let input : Table = {
    ..template,
    rows: Array::makei(count, index => {
      [
        Number((count - index).to_double()),
        Text("a"),
        Number(index.to_double()),
      ]
    }),
  }
  let levels = lag_scale_levels(count)
  let allowance = count * (levels * 30 + 100) + 1000
  let control = { remaining: allowance, max_frames: 100, }
  let workspace = { limit: count * 20 + 100, live: 0, peak: 0, }
  let result = match
    evaluate_lag_rows(
      row_kernel(owner, 0),
      input,
      "lagged",
      count,
      control,
      value_budget({
        max_nodes: count * 20 + 100,
        max_text_bytes: count * 30 + 100,
        max_depth: 10,
        max_work: count * 100 + 100,
      }).unwrap(),
      workspace,
    ) {
    Ok(value) => value
    Err(RowLimit) => fail("lag scale row limit " + count.to_string())
    Err(InvalidRows) => fail("lag scale rows " + count.to_string())
    Err(InvalidRowLimits) => fail("lag scale limits " + count.to_string())
    Err(Comparison(_)) => fail("lag scale comparison " + count.to_string())
    Err(_) => fail("lag scale failure " + count.to_string())
  }
  assert_eq(result.rows.length(), count)
  assert_true(result.rows[0][3] is Null)
  assert_true(result.rows[count - 1][3] is Number(value) && value == 2.0)
  let used = allowance - control.remaining
  assert_true(used <= count * (levels * 4 + 30) + 200)
  assert_true(workspace.peak <= count * 12 + 100)
}

///|
test "lag stays within indexed ordering and linear retention floors" {
  for count in [128, 1024, 8192] {
    check_lag_scale(count)
  }
}
