///|
fn check_take_scale(count : Int) -> Unit raise {
  let input = order_table(
    Array::makei(count, i => Number((count - i).to_double())),
  )
  let allowance = count * 4 + 100
  let control = { remaining: allowance, max_frames: 0, }
  let workspace = { limit: count * 4 + 20, live: 0, peak: 0, }
  let selected = evaluate_take_selection(
    input,
    1L,
    (count - 1).to_int64(),
    count,
    control,
    row_output(),
    workspace,
  ).unwrap()
  assert_eq(selected, (count - 1, 1))
  assert_true(input.rows[selected.0][0] is Number(1.0))
  assert_true(allowance - control.remaining <= count + 20)
  assert_true(workspace.peak <= count * 4 + 20)
}

///|
test "take validates the whole input with linear work and storage" {
  for count in [100, 1000, 10000] {
    check_take_scale(count)
  }
}
