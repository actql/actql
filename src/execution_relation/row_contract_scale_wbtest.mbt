///|
fn json_pick_scale(count : Int) -> Unit raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"inner\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"leaf\":{\"type\":\"number\",\"nullable\":false}}}}}},\"rows\":[{\"id\":1,\"payload\":{\"inner\":{\"leaf\":3}}}]},\"as\":\"seed\"},{\"json_pick\":{\"column\":\"payload\",\"path\":[\"inner\",\"leaf\"],\"output\":\"picked\"}}]",
  )
  let template = row_capture(owner)
  let input = { ..template, rows: Array::makei(count, _ => template.rows[0]), }
  let workspace = { limit: count * 20 + 100, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    input,
    count,
    { remaining: count * 100 + 100, max_frames: 100, },
    value_budget({
      max_nodes: count * 20 + 100,
      max_text_bytes: count * 40 + 100,
      max_depth: 10,
      max_work: count * 50 + 100,
    }).unwrap(),
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), count)
  assert_eq(result.names, ["id", "payload", "picked"])
  assert_true(workspace.peak < count * 20 + 10)
}

///|
fn assert_rows_scale(count : Int, unique : Bool) -> Unit raise {
  let operation = if unique {
    ",{\"assert_rows\":{\"unique_by\":[\"a\",\"b\"]}}"
  } else {
    ",{\"assert_rows\":{\"where\":\"a >= 0\"}}"
  }
  let owner = row_owner(operation)
  let template = row_capture(owner)
  let input = {
    ..template,
    rows: Array::makei(count, i => [Number(i.to_double()), Number(1.0)]),
  }
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
  ).unwrap()
  assert_eq(result.rows.length(), count)
  assert_eq(result.names, ["a", "b"])
  assert_true(workspace.peak < count * 20 + 10)
}

///|
test "json pick and row assertions respect their scaling floors" {
  for count in [100, 1000, 10000] {
    json_pick_scale(count)
    assert_rows_scale(count, false)
    assert_rows_scale(count, true)
  }
}
