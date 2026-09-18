///|
fn derive_scale(count : Int, ordered : Bool) -> Unit raise {
  let operation = if ordered {
    ",{\"derive\":[{\"saved\":\"a\"},{\"a\":\"a + 1\"},{\"next\":\"saved + a\"}]}"
  } else {
    ",{\"derive\":{\"next\":\"a + 1\"}}"
  }
  let owner = row_owner(operation)
  let template = row_capture(owner)
  let input = {
    ..template,
    rows: Array::makei(count, i => [Number(i.to_double()), Number(1.0)]),
  }
  let budget = logical_budget(
    {
      max_input_rows: count.to_int64(),
      max_value_bytes: 1000L,
      max_live_value_bytes: (count * 200).to_int64(),
      max_work: (count * 200).to_int64(),
    },
    1000,
    100,
    10,
  ).unwrap()
  let workspace = { limit: count * 20 + 100, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    input,
    count,
    { remaining: count * 200 + 100, max_frames: 100, },
    value_budget({
      max_nodes: count * 20 + 100,
      max_text_bytes: count * 40 + 100,
      max_depth: 10,
      max_work: count * 50 + 100,
    }).unwrap(),
    workspace,
    ordered_budget=Some(budget),
  ).unwrap()
  assert_eq(result.rows.length(), count)
  assert_eq(result.names.length(), if ordered { 4 } else { 3 })
  assert_true(budget.work < (count * 100 + 10).to_int64())
  assert_eq(budget.rows, count.to_int64())
  assert_eq(budget.live, 0L)
  assert_false(budget.failed)
  assert_true(workspace.peak < count * 20 + 10)
}

///|
test "snapshot and ordered derive work stay linear in rows and bindings" {
  for count in [100, 1000, 10000] {
    derive_scale(count, false)
    derive_scale(count, true)
  }
}
