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
  let workspace = row_workspace(maximum)
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

///|
test "nest metadata construction follows the exact workspace reservation" {
  let width = 512
  let exact_workspace = row_workspace(width * 3)
  let exact_constructed = Ref(false)
  let exact = construct_reserved_nest_metadata(exact_workspace, width, fn() {
    exact_constructed.val = true
    Ok(())
  })
  assert_true(exact is Ok(_))
  assert_true(exact_constructed.val)
  assert_eq(exact_workspace.peak, width * 3)

  let short_workspace = row_workspace(width * 3 - 1)
  let short_constructed = Ref(false)
  let short = construct_reserved_nest_metadata(short_workspace, width, fn() {
    short_constructed.val = true
    Ok(())
  })
  assert_true(short is Err(RowLimit))
  assert_false(short_constructed.val)
  assert_eq((short_workspace.live, short_workspace.peak), (0, 0))
}

///|
fn nest_empty_workspace_attempt(
  limit : Int,
  work_limit? : Int = 100000,
) -> (Result[Unit, RowIssue], Int, Int) raise {
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
  let parents = { ..parent_template, rows: [], }
  let children = { ..child_template, rows: [], }
  let workspace = row_workspace(limit)
  let control = { remaining: work_limit, max_frames: 100, }
  let result = evaluate_nest_rows(
    kernel,
    parents,
    children,
    4,
    control,
    value_budget({
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_depth: 100,
      max_work: 100000,
    }).unwrap(),
    workspace,
    selected_item_limit=Some(1L),
    grouped_byte_limit=Some(10000L),
    attached_byte_limit=Some(10000L),
  ).map(_ => ())
  (result, workspace.peak, work_limit - control.remaining)
}

///|
test "empty nest observes the exact metadata workspace boundary" {
  let (generous, peak, used) = nest_empty_workspace_attempt(10000)
  assert_true(generous is Ok(_))
  // The empty right index is released before projection. At the peak, one
  // key uses two slots, one projected field uses two, and the three output
  // metadata arrays use nine slots.
  let expected_peak = 2 + 2 + 3 * 3
  assert_eq(peak, expected_peak)
  // The two key-name scans, one empty right-index admission, one projected
  // child field, and three output names account for the fixed empty work.
  let expected_work = 98
  assert_eq(used, expected_work)
  let (exact, exact_peak, exact_work) = nest_empty_workspace_attempt(
    expected_peak,
    work_limit=expected_work,
  )
  assert_true(exact is Ok(_))
  assert_eq((exact_peak, exact_work), (expected_peak, expected_work))
  let (short, short_peak, _) = nest_empty_workspace_attempt(expected_peak - 1)
  assert_true(short is Err(RowLimit))
  assert_true(short_peak <= expected_peak - 1)
  let (short_work, _, _) = nest_empty_workspace_attempt(
    expected_peak,
    work_limit=expected_work - 1,
  )
  assert_true(short_work is Err(RowLimit))

  let generated = nest_sequence(3)
  guard @lower.sequence_step(generated.sequence, 2)
    is Some(@lower.NestStep(kernel)) else {
    fail("nest kernel")
  }
  let owner = @lower.nest_kernel_owner(kernel)
  let parents = table_from_capture(
    capture_values(owner, 0, max_rows=4, run_limits().input_values).unwrap(),
  )
  let children = table_from_capture(
    capture_values(owner, 1, max_rows=3, run_limits().input_values).unwrap(),
  )
  assert_kernel_budget_sweep("nest", (control, workspace) => {
    evaluate_nest_rows(
      kernel,
      parents,
      children,
      4,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
      selected_item_limit=Some(3L),
      grouped_byte_limit=Some(10000L),
      attached_byte_limit=Some(10000L),
    )
  })
}
