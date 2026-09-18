///|
fn window_group_scale_input(owner : @lower.BoundPrepared, count : Int) -> Table {
  {
    owner,
    id: @lower.kernel_input(row_kernel(owner, 2)),
    names: ["at", "id", "k", "label", "window_end", "window_start"],
    rows: Array::makei(count, index => {
      let start = index / 64 * 10
      [
        Number(index.to_double()),
        Number(index.to_double()),
        Number((index % 64).to_double()),
        Text("v" + (index % 32).to_string()),
        Number((start + 10).to_double()),
        Number(start.to_double()),
      ]
    }),
  }
}

///|
fn window_group_scale_owner() -> @lower.BoundPrepared {
  bound_pipeline(
    (
      #|[{"values":{"schema":{"at":{"type":"number","nullable":false},"id":{"type":"number","nullable":false},"k":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"at":0,"id":0,"k":0,"label":{"literal":"v0"}}]},"as":"seed"},{"row_window":{"kind":"fixed","time":"at","size":10},"as":"windowed"},{"from":"windowed","window_group":{"by":["k"],"aggregates":{"first":{"fn":"first","field":"label","order_by":[{"id":"asc"}]},"highest":{"fn":"max","field":"label"},"labels":{"fn":"count","field":"label","distinct":true},"last":{"fn":"last","field":"label","order_by":[{"id":"asc"}]},"lowest":{"fn":"min","field":"label"}}}}]
    ),
  )
}

///|
fn window_group_scale_sample(count : Int) -> (Int, Int) raise {
  let owner = window_group_scale_owner()
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: count * 100 + 1000, live: 0, peak: 0, }
  let table = match
    evaluate_rows_with_workspace(
      row_kernel(owner, 2),
      window_group_scale_input(owner, count),
      count,
      control,
      value_budget({
        max_nodes: maximum,
        max_text_bytes: maximum,
        max_depth: 10,
        max_work: maximum,
      }).unwrap(),
      workspace,
    ) {
    Ok(value) => value
    Err(OwnerMismatch) => fail("window group scale owner")
    Err(InputMismatch) => fail("window group scale input")
    Err(InvalidRows) => fail("window group scale rows")
    Err(RowLimit) => fail("window group scale limit")
    Err(Comparison(_)) => fail("window group scale comparison")
    Err(Aggregation(_)) => fail("window group scale aggregate")
    Err(_) => fail("window group scale failure")
  }
  assert_eq(table.rows.length(), count)
  (maximum - control.remaining, workspace.peak)
}

///|
test "window group stays within indexed aggregation scaling floors" {
  for count in [128, 1024, 8192] {
    let (work, peak) = window_group_scale_sample(count)
    let mut levels = 0
    let mut width = 1
    while width < count {
      width *= 2
      levels += 1
    }
    assert_true(work < count * (levels * 20 + 300))
    assert_true(peak < count * 100 + 1000)
  }
}

///|
test "window group accepts exact work and storage boundaries" {
  let owner = window_group_scale_owner()
  let input = window_group_scale_input(owner, 4)
  let maximum = 1000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: 10000, live: 0, peak: 0, }
  let output = value_budget({
    max_nodes: maximum,
    max_text_bytes: maximum,
    max_depth: 10,
    max_work: maximum,
  }).unwrap()
  let kernel = row_kernel(owner, 2)
  let baseline = evaluate_rows_with_workspace(
    kernel, input, 4, control, output, workspace,
  ).unwrap()
  assert_eq(baseline.rows.length(), 4)
  let used = maximum - control.remaining
  let peak = workspace.peak
  for
    (work, slots, succeeds) in [
      (used, peak, true),
      (used - 1, peak, false),
      (used, peak - 1, false),
    ] {
    let result = evaluate_rows_with_workspace(
      kernel,
      input,
      4,
      { remaining: work, max_frames: 100, },
      value_budget({
        max_nodes: maximum,
        max_text_bytes: maximum,
        max_depth: 10,
        max_work: maximum,
      }).unwrap(),
      { limit: slots, live: 0, peak: 0, },
    )
    assert_eq(result is Ok(_), succeeds)
  }
  assert_true(
    evaluate_rows_with_workspace(
      kernel,
      input,
      3,
      { remaining: used, max_frames: 100, },
      value_budget({
        max_nodes: maximum,
        max_text_bytes: maximum,
        max_depth: 10,
        max_work: maximum,
      }).unwrap(),
      { limit: peak, live: 0, peak: 0, },
    )
    is Err(RowLimit),
  )
}
