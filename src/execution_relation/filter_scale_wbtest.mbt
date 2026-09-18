///|
fn filter_scale(count : Int, keep : Bool) -> Unit raise {
  let owner = row_owner(",{\"filter\":\"a > 0\"}")
  let template = row_capture(owner)
  let input = {
    ..template,
    rows: Array::makei(count, i => {
      [
        Number(if keep || i % 2 == 0 { 1.0 } else { -1.0 }),
        Number(i.to_double()),
      ]
    }),
  }
  let budget = logical_budget(
    {
      max_input_rows: count.to_int64(),
      max_value_bytes: 1000L,
      max_live_value_bytes: (count * 100).to_int64(),
      max_work: (count * 100).to_int64(),
    },
    1000,
    100,
    10,
  ).unwrap()
  let workspace = { limit: count * 10 + 100, live: 0, peak: 0, }
  let output = value_budget({
    max_nodes: count * 10 + 100,
    max_text_bytes: count * 20 + 100,
    max_depth: 10,
    max_work: count * 20 + 100,
  }).unwrap()
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    input,
    count,
    { remaining: count * 100 + 100, max_frames: 100, },
    output,
    workspace,
    ordered_budget=Some(budget),
  ).unwrap()
  assert_eq(result.rows.length(), if keep { count } else { (count + 1) / 2 })
  assert_true(budget.work < (count * 50 + 10).to_int64())
  assert_eq(budget.rows, count.to_int64())
  assert_eq(budget.live, 0L)
  assert_false(budget.failed)
  assert_true(workspace.live < count * 10 + 10)
  assert_true(workspace.peak < count * 10 + 10)
}

///|
test "filter work stays linear across selectivity distributions" {
  for count in [100, 1000, 10000] {
    filter_scale(count, true)
    filter_scale(count, false)
  }
}
