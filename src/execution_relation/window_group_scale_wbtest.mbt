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
  let kernel = row_kernel(owner, 2)
  assert_kernel_budget_sweep("row", (control, workspace) => {
    evaluate_rows_with_workspace(
      kernel,
      input,
      4,
      control,
      value_budget({
        max_nodes: maximum,
        max_text_bytes: maximum,
        max_depth: 10,
        max_work: maximum,
      }).unwrap(),
      workspace,
    )
  })
  assert_true(
    evaluate_rows_with_workspace(
      kernel,
      input,
      3,
      { remaining: maximum, max_frames: 100, },
      value_budget({
        max_nodes: maximum,
        max_text_bytes: maximum,
        max_depth: 10,
        max_work: maximum,
      }).unwrap(),
      row_workspace(maximum),
    )
    is Err(RowLimit),
  )
}

///|
test "empty window group has an independently bounded resource path" {
  let owner = window_group_scale_owner()
  let kernel = row_kernel(owner, 2)
  let input = window_group_scale_input(owner, 0)
  let run = (work_limit, workspace_limit) => {
    let control = { remaining: work_limit, max_frames: 100, }
    let workspace = row_workspace(workspace_limit)
    let result = evaluate_rows_with_workspace(
      kernel,
      input,
      0,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
    (result, workspace.peak, work_limit - control.remaining)
  }
  // This fixed empty case still admits the two checked window coordinates,
  // five aggregate descriptors, their names, and output schema metadata.
  let expected_work = 195
  let expected_peak = 51
  let (result, peak, used) = run(expected_work, expected_peak)
  assert_true(result is Ok(_))
  assert_eq((peak, used), (expected_peak, expected_work))
  assert_true(run(expected_work - 1, expected_peak).0 is Err(RowLimit))
  assert_true(run(expected_work, expected_peak - 1).0 is Err(RowLimit))
}

///|
fn numeric_window_group_workspace_attempt(
  limit : Int,
) -> (Result[Table, RowIssue], Int) {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"at":{"type":"number","nullable":false},"id":{"type":"number","nullable":false},"n":{"type":"number","nullable":true}},"rows":[{"at":0,"id":0,"n":1}]} ,"as":"seed"},{"row_window":{"kind":"fixed","time":"at","size":10},"as":"windowed"},{"from":"windowed","window_group":{"by":[],"aggregates":{"mean":{"fn":"avg","field":"n"},"total":{"fn":"sum","field":"n"}}}}]
    ),
  )
  let input : Table = {
    owner,
    id: @lower.kernel_input(row_kernel(owner, 2)),
    names: ["at", "id", "n", "window_end", "window_start"],
    rows: [
      [Number(0), Number(0), Number(1), Number(10), Number(0)],
      [Number(1), Number(1), Number(2), Number(10), Number(0)],
      [Number(11), Number(2), Number(3), Number(20), Number(10)],
    ],
  }
  let profile = @numeric.builtin_profile()
  let reduction = @numeric.select(
    profile,
    @numeric.member_cid_at(profile, 0).unwrap(),
  ).unwrap()
  let numeric = numeric_aggregate_execution((
    _step,
    name,
    _occurrence,
    contributors,
    expected_count,
    max_work,
  ) => {
    Some(
      @numeric.execute(
        reduction,
        if name == "mean" {
          @numeric.Average
        } else {
          @numeric.Sum
        },
        contributors,
        expected_count,
        max_work,
      ),
    )
  })
  let workspace = { limit, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 2),
    input,
    3,
    { remaining: 100000, max_frames: 100, },
    value_budget({
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_depth: 10,
      max_work: 100000,
    }).unwrap(),
    workspace,
    numeric=Some(numeric),
  )
  (result, workspace.peak)
}

///|
test "numeric window group arrays respect the exact workspace boundary" {
  let (baseline, peak) = numeric_window_group_workspace_attempt(10000)
  assert_true(baseline is Ok(_))
  let (exact, exact_peak) = numeric_window_group_workspace_attempt(peak)
  assert_true(exact is Ok(_))
  assert_eq(exact_peak, peak)
  let (short, short_peak) = numeric_window_group_workspace_attempt(peak - 1)
  assert_true(short is Err(RowLimit))
  assert_true(short_peak <= peak - 1)
}
