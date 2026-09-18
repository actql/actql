///|
fn top_k_scale_table(owner : @lower.BoundPrepared, count : Int) -> Table {
  let template = table_from_capture(
    capture_input(
      owner,
      0,
      [input_cursor("{\"n\":1,\"s\":\"a\"}")],
      max_rows=1,
      run_limits().input_values,
    ).unwrap(),
  )
  {
    ..template,
    rows: Array::makei(count, i => {
      [
        Number((count - i).to_double()),
        Text(if i % 2 == 0 { "a" } else { "b" }),
      ]
    }),
  }
}

///|
fn top_k_scale_levels(count : Int) -> Int {
  let mut size = 1
  let mut levels = 0
  while size < count {
    size *= 2
    levels += 1
  }
  levels
}

///|
fn check_top_k_scale(count : Int, partitioned : Bool) -> Unit raise {
  let tail = if partitioned {
    "[{\"top_k_by\":{\"partition_by\":[\"s\"],\"k\":3,\"by\":[{\"n\":\"desc\"}]}}]"
  } else {
    "[{\"top_k\":{\"k\":6,\"by\":[{\"s\":\"asc\"},{\"n\":\"desc\"}]}}]"
  }
  let owner = take_key_owner(tail)
  let input = top_k_scale_table(owner, count)
  let levels = top_k_scale_levels(count)
  let allowance = count * (levels * 30 + 100) + 1000
  let control = { remaining: allowance, max_frames: 100, }
  let workspace = { limit: count * 8 + 100, live: 0, peak: 0, }
  let selected = evaluate_top_k_selection(
    row_kernel(owner, 0),
    input,
    if partitioned {
      3L
    } else {
      6L
    },
    count,
    control,
    value_budget({
      max_nodes: count * 20 + 100,
      max_text_bytes: count * 20 + 100,
      max_depth: 10,
      max_work: count * 100 + 100,
    }).unwrap(),
    workspace,
  ).unwrap()
  assert_eq(selected.length(), 6)
  assert_eq(
    selected,
    if partitioned {
      [0, 2, 4, 1, 3, 5]
    } else {
      [0, 2, 4, 6, 8, 10]
    },
  )
  let used = allowance - control.remaining
  assert_true(used <= count * (levels * 16 + 40) + 200)
  assert_true(workspace.peak <= count * 6 + 100)
}

///|
test "global and partitioned top-k stay within indexed scaling floors" {
  for count in [128, 1024, 8192] {
    check_top_k_scale(count, false)
    check_top_k_scale(count, true)
  }
}

///|
test "large global and partitioned top-k budgets are exact" {
  let count = 1000
  for partitioned in [false, true] {
    let tail = if partitioned {
      "[{\"top_k_by\":{\"partition_by\":[\"s\"],\"k\":3," +
      "\"by\":[{\"n\":\"desc\"}]}}]"
    } else {
      "[{\"top_k\":{\"k\":6," + "\"by\":[{\"s\":\"asc\"},{\"n\":\"desc\"}]}}]"
    }
    let owner = take_key_owner(tail)
    let input = top_k_scale_table(owner, count)
    let maximum = 10000000
    let control = { remaining: maximum, max_frames: 100, }
    let workspace = { limit: maximum, live: 0, peak: 0, }
    let expected = evaluate_top_k_selection(
      row_kernel(owner, 0),
      input,
      if partitioned {
        3L
      } else {
        6L
      },
      count,
      control,
      value_budget({
        max_nodes: maximum,
        max_text_bytes: maximum,
        max_depth: 10,
        max_work: maximum,
      }).unwrap(),
      workspace,
    ).unwrap()
    assert_eq(expected.length(), 6)
    let used = maximum - control.remaining
    let peak = workspace.peak
    for
      (work, entries, good) in [
        (used, peak, true),
        (used - 1, peak, false),
        (used, peak - 1, false),
      ] {
      let result = evaluate_top_k_selection(
        row_kernel(owner, 0),
        input,
        if partitioned {
          3L
        } else {
          6L
        },
        count,
        { remaining: work, max_frames: 100, },
        value_budget({
          max_nodes: maximum,
          max_text_bytes: maximum,
          max_depth: 10,
          max_work: maximum,
        }).unwrap(),
        { limit: entries, live: 0, peak: 0, },
      )
      if good {
        assert_eq(result.unwrap(), expected)
      } else {
        assert_true(result is Err(RowLimit))
      }
    }
  }
}
