///|
fn row_window_scale_sample(count : Int, sliding : Bool) -> (Int, Int) raise {
  let source = "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\"," +
    "\"nullable\":false},\"id\":{\"type\":\"number\"," +
    "\"nullable\":false}},\"rows\":[{\"at\":0,\"id\":0}]}," +
    "\"as\":\"seed\"},{\"row_window\":{\"kind\":\"" +
    (if sliding { "sliding" } else { "fixed" }) +
    "\",\"time\":\"at\",\"size\":10" +
    (if sliding { ",\"step\":5" } else { "" }) +
    "}}]"
  let owner = bound_pipeline(source)
  guard @lower.sequence_step(prepared_sequence(owner), 1)
    is Some(@lower.WindowStep(window)) else {
    abort("row window scale lowering")
  }
  let input : Table = {
    owner,
    id: "values_0",
    names: ["at", "id"],
    rows: Array::makei(count, index => {
      [Number(index.to_double()), Number(index.to_double())]
    }),
  }
  let output_count = if sliding { count * 2 } else { count }
  let allowance = output_count * 20 + count * 10 + 1000
  let control = { remaining: allowance, max_frames: 100, }
  let workspace = {
    limit: output_count * 8 + count * 4 + 100,
    live: 0,
    peak: 0,
  }
  let result = match
    evaluate_window_rows(
      window,
      input,
      output_count,
      control,
      value_budget({
        max_nodes: output_count * 20 + 100,
        max_text_bytes: output_count * 40 + 100,
        max_depth: 10,
        max_work: output_count * 100 + 100,
      }).unwrap(),
      workspace,
    ) {
    Ok(value) => value
    Err(RowLimit) => abort("row window scale limit")
    Err(WindowArithmetic(_)) => abort("row window scale arithmetic")
    Err(_) => abort("row window scale failure")
  }
  assert_eq(result.rows.length(), output_count)
  (allowance - control.remaining, workspace.peak)
}

///|
test "row window passes the common kernel budget sweep" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":0,\"id\":0}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":5}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 1)
    is Some(@lower.WindowStep(window)) else {
    fail("row window lowering")
  }
  let input : Table = {
    owner,
    id: "values_0",
    names: ["at", "id"],
    rows: [[Number(0), Number(0)], [Number(1), Number(1)]],
  }
  assert_kernel_budget_sweep("window", (control, workspace) => {
    evaluate_window_rows(
      window,
      input,
      4,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
  })
}

///|
test "row windows scale with input rows and emitted memberships" {
  for count in [128, 1024, 8192] {
    for sliding in [false, true] {
      let (work, peak) = row_window_scale_sample(count, sliding)
      let output_count = if sliding { count * 2 } else { count }
      assert_true(work <= count * 10 + output_count * 10 + 100)
      assert_true(peak <= count * 4 + output_count * 6 + 100)
    }
  }
}

///|
test "empty row window reserves its output schema before allocation" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 1)
    is Some(@lower.WindowStep(window)) else {
    fail("row window lowering")
  }
  let input : Table = { owner, id: "values_0", names: ["at", "id"], rows: [], }
  // Two input names and four output names coexist even without rows.
  for (limit, succeeds) in [(6, true), (5, false)] {
    let workspace = row_workspace(limit)
    let result = evaluate_window_rows(
      window,
      input,
      0,
      { remaining: 10000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
    assert_eq(result is Ok(_), succeeds)
    assert_eq(workspace.peak, if succeeds { 6 } else { 2 })
  }
}
