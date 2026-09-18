///|
fn sort_scale_levels(count : Int) -> Int {
  let mut size = 1
  let mut levels = 0
  while size < count {
    size *= 2
    levels += 1
  }
  levels
}

///|
fn check_sort_scale(count : Int) -> Unit raise {
  let owner = sort_seed(",{\"sort\":[{\"id\":\"asc\"},{\"k\":\"desc\"}]}")
  let template = row_capture(owner)
  let payload = template.rows[0][2]
  let input : Table = {
    ..template,
    rows: Array::makei(count, i => {
      [Number((count - i).to_double()), Number((i % 7).to_double()), payload]
    }),
  }
  let levels = sort_scale_levels(count)
  let allowance = count * (levels * 10 + 100) + 1000
  let control = { remaining: allowance, max_frames: 100, }
  let workspace = { limit: count * 30 + 100, live: 0, peak: 0, }
  let indices = evaluate_sort_selection(
    row_kernel(owner, 1),
    input,
    count,
    control,
    value_budget({
      max_nodes: count * 20 + 100,
      max_text_bytes: count * 40 + 100,
      max_depth: 10,
      max_work: count * 100 + 100,
    }).unwrap(),
    workspace,
  ).unwrap()
  assert_eq(indices.length(), count)
  assert_eq(indices[0], count - 1)
  assert_eq(indices[count - 1], 0)
  let used = allowance - control.remaining
  assert_true(used <= count * (levels * 2 + 10) + 100)
  assert_true(workspace.peak <= count * 10 + 100)
}

///|
test "stable compound sort stays within indexed scaling floors" {
  for count in [128, 1024, 8192] {
    check_sort_scale(count)
  }
}
