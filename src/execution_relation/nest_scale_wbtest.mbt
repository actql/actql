///|
fn nest_scale_sample(count : Int) -> (Int, Int) raise {
  let generated = nest_sequence(1)
  guard @lower.sequence_step(generated.sequence, 2)
    is Some(@lower.NestStep(kernel)) else {
    fail("nest kernel was not prepared")
  }
  let owner = @lower.nest_kernel_owner(kernel)
  let parent_template = table_from_capture(
    capture_values(owner, 0, max_rows=4, run_limits().input_values).unwrap(),
  )
  let child_template = table_from_capture(
    capture_values(owner, 1, max_rows=3, run_limits().input_values).unwrap(),
  )
  let parents = {
    ..parent_template,
    rows: Array::makei(count, index => {
      parent_template.names.map(name => {
        match name {
          "id" | "key" => Number(index.to_double())
          _ => abort("unexpected nest parent field")
        }
      })
    }),
  }
  let children = {
    ..child_template,
    rows: Array::makei(count, index => {
      let value = count - index - 1
      child_template.names.map(name => {
        match name {
          "child_id" | "key" | "value" => Number(value.to_double())
          _ => abort("unexpected nest child field")
        }
      })
    }),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace : RowWorkspace = { limit: maximum, live: 0, peak: 0, }
  let output = value_budget({
    max_nodes: maximum,
    max_text_bytes: maximum,
    max_depth: 100,
    max_work: maximum,
  }).unwrap()
  let table = evaluate_nest_rows(
    kernel,
    parents,
    children,
    count,
    control,
    output,
    workspace,
    selected_item_limit=Some(1L),
    grouped_byte_limit=Some(10000000L),
    attached_byte_limit=Some(10000000L),
  ).unwrap()
  assert_eq(table.rows.length(), count)
  assert_true(table.rows[0][0] is Number(0))
  let first = nested_amounts(table.rows[0])
  assert_true(first.length() == 1 && first[0] is Number(0))
  (maximum - control.remaining, workspace.peak)
}

///|
test "nest indexed correlation scales with inputs and emitted payload" {
  for count in [128, 1024, 8192] {
    let levels = binary_scale_levels(count)
    let (work, peak) = nest_scale_sample(count)
    assert_true(work <= count * (levels * 30 + 250) + 1000)
    assert_true(peak <= count * 20 + 100)
  }
}
