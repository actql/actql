///|
test "fragment runtime bounds are explicit request-bounded owner-bound and fresh" {
  let fragment = check_generated_fragment(
    admission_candidate("7"),
    material_demands(),
    registry_limits(),
  ).unwrap()
  let limits : LogicalLimits = {
    max_input_rows: 10L,
    max_value_bytes: 1000L,
    max_live_value_bytes: 10000L,
    max_work: 100000L,
  }
  let context = prepare_fragment_runtime_context(
    fragment,
    limits,
    registry_limits(),
  ).unwrap()
  assert_true(physical_equal(context.fragment, fragment))
  assert_true(
    prepare_fragment_runtime_context(
      fragment,
      { ..limits, max_input_rows: 11L, },
      registry_limits(),
    )
    is Err(ExceedsRequest),
  )
  assert_true(
    prepare_fragment_runtime_context(
      fragment,
      { ..limits, max_value_bytes: 1001L, },
      registry_limits(),
    )
    is Err(ExceedsRequest),
  )
  assert_true(
    prepare_fragment_runtime_context(
      fragment,
      { ..limits, max_work: -1L, },
      registry_limits(),
    )
    is Err(InvalidLimits),
  )
  let first = fragment_runtime_for_kernel(context, context.kernel).unwrap()
  charge_logical_work(first, 1L).unwrap()
  let second = fragment_runtime_for_kernel(context, context.kernel).unwrap()
  assert_eq(first.work, 1L)
  assert_eq(second.work, 0L)
  let other = prepare_fragment_runtime_context(
    check_generated_fragment(
      admission_candidate("7"),
      material_demands(),
      registry_limits(),
    ).unwrap(),
    limits,
    registry_limits(),
  ).unwrap()
  assert_true(
    fragment_runtime_for_kernel(context, other.kernel) is Err(KernelMismatch),
  )
}

///|
test "checked fragment runtime budget reaches the shared evaluator without resetting work" {
  let fragment = check_generated_fragment(
    admission_candidate("7"),
    material_demands(),
    registry_limits(),
  ).unwrap()
  let context = prepare_fragment_runtime_context(
    fragment,
    {
      max_input_rows: 2L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
    registry_limits(),
  ).unwrap()
  let budget = fragment_runtime_for_kernel(context, context.kernel).unwrap()
  let input = row_capture(@lower.kernel_owner(context.kernel))
  let output = evaluate_rows_with_workspace(
    context.kernel,
    input,
    2,
    { remaining: 100000, max_frames: 100, },
    row_output(),
    { limit: 100000, live: 0, peak: 0, },
    ordered_budget=Some(budget),
  ).unwrap()
  assert_eq(output.rows.length(), 2)
  assert_true(budget.work > 0L)
  assert_eq(budget.rows, 2L)
  assert_eq(budget.live, 0L)
  let denied = prepare_fragment_runtime_context(
    context.fragment,
    {
      max_input_rows: 1L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
    registry_limits(),
  ).unwrap()
  let limited = fragment_runtime_for_kernel(denied, denied.kernel).unwrap()
  assert_true(
    evaluate_rows_with_workspace(
      denied.kernel,
      input,
      2,
      { remaining: 100000, max_frames: 100, },
      row_output(),
      { limit: 100000, live: 0, peak: 0, },
      ordered_budget=Some(limited),
    )
    is Err(LogicalRows(InputRowLimit)),
  )
}
