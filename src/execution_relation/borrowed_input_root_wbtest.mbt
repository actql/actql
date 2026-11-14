///|
fn borrowed_input_root_row() -> (BoundedBindingRow, Array[String]) raise {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"tag\":\"é\"}]",
    distinct=true,
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
  let schema = producer_read_schema(input)
  let names = Array::makei(@schema.field_count(schema), index => {
    @schema.reference_name(@schema.field_at(schema, index).unwrap().name)
  })
  (
    { input: CompletedBindingInput(input), row: 0, width: names.length(), },
    names,
  )
}

///|
fn borrowed_input_root_growth() -> WorkspaceGrowth {
  {
    ..working_growth_fixture(_ => Ok(())),
    initial_slots: 0,
    initial_live: 0L,
    live_ceiling: 536870912L,
  }
}

///|
test "borrowed input root keeps full semantic bytes and work with paid registry storage" {
  let (row, names) = borrowed_input_root_row()
  let growth = borrowed_input_root_growth()
  let workspace = { ..row_workspace(10), growth: Some(growth), }
  let budget = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
  assert_true(reserve_slots(workspace, 1))
  let root = retain_bounded_input_logical_row(budget, names, row).unwrap()
  // Canonical UTF-8 {"id":1,"tag":"é"}: full occurrence debit remains19.
  assert_eq((root.bytes, root.workspace_bytes), (19L, 0L))
  assert_eq((budget.live, budget.work), (19L, 10L))
  assert_eq(growth.logical, 0L)
  assert_eq(growth.funded, 256L)
  release_logical_root(budget, root).unwrap()
  release_slots(workspace, 1)
  assert_eq(
    (budget.live, budget.work, growth.logical, growth.slots),
    (0L, 10L, 0L, 0),
  )
  assert_eq(growth.funded, 256L)
}

///|
test "borrowed input root preserves live byte work and lifetime refusal" {
  let (row, names) = borrowed_input_root_row()
  let short = test_logical_budget(100L, 18L)
  assert_true(
    retain_bounded_input_logical_row(short, names, row) is Err(LiveValueLimit),
  )
  assert_eq((short.live, short.work), (0L, 10L))
  let work = test_logical_budget(9L, 100L)
  assert_true(retain_bounded_input_logical_row(work, names, row) is Err(_))
  assert_true(work.failed)
  let original = test_logical_budget(100L, 100L)
  let root = retain_bounded_input_logical_row(original, names, row).unwrap()
  let scope = expression_roots(original, 10)
  let lease = register_scope_root(scope, root).unwrap()
  // This read root cannot silently become a mutable uncharged object body.
  assert_true(grow_object_root(lease, 1L) is Err(InvalidRootLifetime))
  release_expression_root(lease).unwrap()
  assert_eq((original.live, original.work), (0L, 10L))
}

///|
test "general row and recursive value roots retain their original physical recipe" {
  let (row, names) = borrowed_input_root_row()
  let growth = borrowed_input_root_growth()
  let budget = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
  let root = retain_logical_row(budget, names, row).unwrap()
  assert_eq((root.bytes, root.workspace_bytes, growth.logical), (19L, 19L, 19L))
  assert_eq(growth.funded, 19L * (256L + 8L))
  release_logical_root(budget, root).unwrap()
  assert_eq(growth.logical, 0L)
  let recursive = retain_logical_value(budget, logical_literal("{\"x\":[1,2]}")).unwrap()
  assert_true(recursive.workspace_bytes > 0L)
  assert_eq(recursive.workspace_bytes, recursive.bytes)
  release_logical_root(budget, recursive).unwrap()
  assert_eq((budget.live, growth.logical), (0L, 0L))
}

///|
test "borrowed and zero byte roots cannot revive failed or reentered growth" {
  let (row, names) = borrowed_input_root_row()
  for failed in [true, false] {
    let growth = borrowed_input_root_growth()
    growth.failed = failed
    growth.busy = !failed
    let budget = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
    assert_true(
      retain_bounded_input_logical_row(budget, names, row)
      is Err(LiveValueLimit),
    )
    assert_true(growth.failed)
    assert_eq((budget.live, growth.logical), (0L, 0L))
    let generic = { ..test_logical_budget(100L, 100L), growth: Some(growth), }
    assert_true(reserve_logical_bytes(generic, 0L) is Err(LiveValueLimit))
    assert_eq((generic.live, growth.logical), (0L, 0L))
  }
}
