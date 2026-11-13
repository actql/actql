///|
fn funded_output_root_fixture(
  growth : WorkspaceGrowth,
  row : BoundedBindingRow,
  names : Array[String],
) -> ValueBudget raise {
  let output = value_budget(run_limits().output_values).unwrap()
  output.retention = Some(growth)
  assert_true(retain_row(row, names, output))
  assert_eq((output.nodes, output.text, output.work), (3, 7, 10))
  output
}

///|
fn funded_output_root_usage(output : ValueBudget) -> ValueUsage {
  { nodes: output.nodes, text_bytes: output.text, work: output.work, }
}

///|
test "funded output root retains full semantic debit without a second body reservation" {
  let (row, names) = borrowed_input_root_row()
  let growth = { ..borrowed_input_root_growth(), retained_outputs: Some(0L), }
  let output = funded_output_root_fixture(growth, row, names)
  assert_true(fund_output_retention(output, output.nodes, output.text))
  // Three complete logical nodes and seven original UTF-8 text bytes.
  assert_eq(output.retention_funded, 3L * 256L + 7L * 8L)
  let paid = growth.funded
  let budget = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
  let root = retain_funded_output_logical_row(
    budget,
    names,
    row,
    output,
    funded_output_root_usage(output),
  ).unwrap()
  assert_eq((root.bytes, root.workspace_bytes), (19L, 0L))
  assert_eq((budget.live, budget.work, growth.logical), (19L, 10L, 0L))
  assert_eq(growth.funded, paid)
  release_logical_root(budget, root).unwrap()
  assert_eq((budget.live, budget.work, growth.logical), (0L, 10L, 0L))
  assert_eq(growth.funded, paid)
}

///|
test "unfunded later row and foreign output funding keep the generic body recipe" {
  let (row, names) = borrowed_input_root_row()
  for foreign in [false, true] {
    let original = {
      ..borrowed_input_root_growth(),
      retained_outputs: Some(0L),
    }
    let supplied = if foreign {
      { ..borrowed_input_root_growth(), retained_outputs: Some(0L), }
    } else {
      original
    }
    let output = funded_output_root_fixture(supplied, row, names)
    assert_true(fund_output_retention(output, output.nodes, output.text))
    if !foreign {
      // Same budget, genuinely measured next row, but its DATA is not funded.
      assert_true(retain_row(row, names, output))
    }
    let budget = { ..test_logical_budget(100L, 100L), growth: Some(original), }
    let root = retain_funded_output_logical_row(
      budget,
      names,
      row,
      output,
      funded_output_root_usage(output),
    ).unwrap()
    assert_eq(
      (root.bytes, root.workspace_bytes, original.logical),
      (19L, 19L, 19L),
    )
    release_logical_root(budget, root).unwrap()
    assert_eq((budget.live, original.logical), (0L, 0L))
  }
}

///|
test "funded output retains exact live byte work and released-root refusal" {
  let (row, names) = borrowed_input_root_row()
  let growth = { ..borrowed_input_root_growth(), retained_outputs: Some(0L), }
  let output = funded_output_root_fixture(growth, row, names)
  assert_true(fund_output_retention(output, output.nodes, output.text))
  let usage = funded_output_root_usage(output)
  let short = { ..test_logical_budget(100L, 18L), growth: Some(growth), }
  assert_true(
    retain_funded_output_logical_row(short, names, row, output, usage)
    is Err(LiveValueLimit),
  )
  assert_eq((short.live, short.work), (0L, 10L))
  let work = { ..test_logical_budget(9L, 100L), growth: Some(growth), }
  assert_true(
    retain_funded_output_logical_row(work, names, row, output, usage) is Err(_),
  )
  assert_true(work.failed)
  let exact = { ..test_logical_budget(10L, 19L), growth: Some(growth), }
  let root = retain_funded_output_logical_row(exact, names, row, output, usage).unwrap()
  release_logical_root(exact, root).unwrap()
  assert_true(release_logical_root(exact, root) is Err(InvalidRootLifetime))
}

///|
test "funded output transfers its full root before producing roots retire" {
  let (row, names) = borrowed_input_root_row()
  let growth = { ..borrowed_input_root_growth(), retained_outputs: Some(0L), }
  let output = funded_output_root_fixture(growth, row, names)
  let budget = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
  let scope = expression_roots(budget, 10)
  let input_root = retain_logical_row(budget, names, row).unwrap()
  let input = register_scope_root(scope, input_root).unwrap()
  let slot = track_expression_root(scope, Number(1.0), true).unwrap()
  assert_true(fund_output_retention(output, output.nodes, output.text))
  row_event_funded_output(
    scope,
    names,
    row,
    [slot],
    input,
    output,
    funded_output_root_usage(output),
  ).unwrap()
  assert_true(input.root.released && slot.root.released)
  assert_eq(budget.live, 19L)
  let live = scope.slots.filter_map(value => value)
  assert_eq(live.length(), 1)
  assert_eq((live[0].bytes, live[0].workspace_bytes), (19L, 0L))
  cleanup_expression_roots(scope)
  assert_eq((budget.live, growth.logical), (0L, 0L))
}

///|
test "refused output funding cannot issue a zero-body root or revive failed growth" {
  let (row, names) = borrowed_input_root_row()
  let growth = {
    ..borrowed_input_root_growth(),
    retained_outputs: Some(0L),
    reserve: _ => Err(WorkspaceBudgetUnavailable),
  }
  let output = funded_output_root_fixture(growth, row, names)
  assert_false(fund_output_retention(output, output.nodes, output.text))
  assert_true(growth.failed)
  assert_eq(output.retention_funded, 0L)
  let budget = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
  assert_true(
    retain_funded_output_logical_row(
      budget,
      names,
      row,
      output,
      funded_output_root_usage(output),
    )
    is Err(LiveValueLimit),
  )
  assert_eq((budget.live, growth.logical, growth.funded), (0L, 0L, 0L))
}
