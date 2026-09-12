///|
test "checked sort selection reads every layout with identical output and budgets" {
  let owner = sort_seed(",{\"sort\":[{\"id\":\"asc\"}]}")
  let captured = capture_values(owner, 0, max_rows=3, run_limits().input_values).unwrap()
  let kernel = row_kernel(owner, 1)
  let mut baseline : (Int, Int)? = None
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let input = layout_relation(captured, candidate)
    let control = { remaining: 100000, max_frames: 100, }
    let workspace = { limit: 100000, live: 0, peak: 0, }
    let indices = evaluate_sort_selection(
      kernel,
      input,
      3,
      control,
      row_output(),
      workspace,
    ).unwrap()
    assert_eq(indices, [1, 2, 0])
    let counters = (control.remaining, workspace.peak)
    match baseline {
      None => baseline = Some(counters)
      Some(expected) => assert_eq(counters, expected)
    }
    let sorted = {
      ..input,
      storage: select_layout_rows(
        input.storage,
        indices,
        layout_allocation(100000, 100000, 100000),
      ).unwrap(),
    }
    assert_eq(
      evaluate_take_selection(
        sorted,
        1L,
        1L,
        3,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
      ).unwrap(),
      (1, 1),
    )
    assert_true(layout_cell(sorted.storage, 1, 0) is Some(Number(2)))
    // All rows must still be admitted even if the selected range would be empty.
    assert_true(
      evaluate_take_selection(
        sorted,
        1L,
        100L,
        2,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
      )
      is Err(RowLimit),
    )
  }
}

///|
test "checked dedupe and distinct selection preserve payload without row materialization" {
  let owner = bound_pipeline(
    dedupe_source(
      "[{\"k\":2,\"rank\":1,\"payload\":[10]},{\"k\":1,\"rank\":2,\"payload\":[20]},{\"k\":2,\"rank\":3,\"payload\":[30]},{\"k\":1,\"rank\":4,\"payload\":[40]}]",
      "[\"k\"]", "",
    ),
  )
  let captured = capture_values(owner, 0, max_rows=4, run_limits().input_values).unwrap()
  let kernel = row_kernel(owner, 1)
  let mut baseline : (Int, Int)? = None
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let input = layout_relation(captured, candidate)
    let control = { remaining: 100000, max_frames: 100, }
    let workspace = { limit: 100000, live: 0, peak: 0, }
    assert_eq(
      evaluate_dedupe_selection(
        kernel,
        input,
        4,
        control,
        row_output(),
        workspace,
      ).unwrap(),
      [2, 3],
    )
    let counters = (control.remaining, workspace.peak)
    match baseline {
      None => baseline = Some(counters)
      Some(expected) => assert_eq(counters, expected)
    }
    let projected = {
      ..input,
      names: ["k"],
      storage: project_layout(
        input.storage,
        [0],
        layout_allocation(100000, 100000, 100000),
      ).unwrap(),
    }
    assert_eq(
      evaluate_distinct_selection(
        projected,
        4,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
      ).unwrap(),
      [0, 1],
    )
    assert_true(
      layout_cell(input.storage, 2, 1) is Some(Captured(@admitted.Array(_))),
    )
  }
}
