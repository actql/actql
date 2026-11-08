///|
#cfg(target="js")
fn text_test_capacity() -> (Int64, Int64, Int64) {
  (4800256L, 352L, 256L)
}

///|
#cfg(not(target="js"))
fn text_test_capacity() -> (Int64, Int64, Int64) {
  (2400256L, 304L, 272L)
}

///|
fn measured_text_root_fixture(
  reserve : (Int64) -> Result[Unit, WorkspaceGrowthIssue],
) -> (WorkspaceGrowth, RowWorkspace, LogicalBudget, ExpressionRootLease) {
  let growth = working_growth_fixture(reserve)
  let workspace = { ..row_workspace(10000), growth: Some(growth), }
  let limits : LogicalLimits = {
    max_input_rows: 1L,
    max_value_bytes: 1000000L,
    max_live_value_bytes: 1000000L,
    max_work: 1000000L,
  }
  let budget = logical_budget(limits, 1000000, 100, 10, growth=Some(growth)).unwrap()
  let root = reserve_text_logical_bytes(budget, 2L).unwrap()
  let lease = register_scope_root(expression_roots(budget, 0), root).unwrap()
  (growth, workspace, budget, lease)
}

///|
test "measured Text uses one node and cached UTF16 geometry rather than wire bytes" {
  let (large, small, empty) = text_test_capacity()
  assert_eq(measured_text_capacity(150000, 150002), Some(large))
  assert_eq(measured_text_capacity(3, 8), Some(small))
  // Escapes change wire bytes, not the original UTF-16 payload allocation.
  assert_eq(measured_text_capacity(3, 20), Some(small))
  assert_eq(measured_text_capacity(0, 2), Some(empty))
  assert_true(measured_text_capacity(-1, 2) is None)
  assert_true(measured_text_capacity(4, 3) is None)
  let calls : Array[Int64] = []
  let (growth, workspace, budget, root) = measured_text_root_fixture(bytes => {
    calls.push(bytes)
    if bytes <= 6000000L {
      Ok(())
    } else {
      Err(WorkspaceUnavailable)
    }
  })
  grow_object_root(root, 150000L).unwrap()
  assert_eq(calls.length(), 0)
  assert_eq(growth.logical, 0L)
  reserve_measured_text_buffer(root, workspace, 150000, 150002).unwrap()
  assert_eq(calls, [large])
  assert_eq(root.root.text_capacity, Some(large))
  assert_eq(workspace.live, 0)
  assert_eq(growth.slots, 0)
  assert_eq(growth.text, large)
  release_expression_root(root).unwrap()
  assert_eq(budget.live, 0L)
  assert_eq(growth.text, 0L)
  assert_eq(growth.funded, large)
}

///|
test "measured Text refusal or foreign workspace cannot allocate and preserves root cleanup" {
  for foreign in [false, true] {
    let calls = Ref(0)
    let (growth, workspace, budget, root) = measured_text_root_fixture(_ => {
      calls.val += 1
      Err(WorkspaceUnavailable)
    })
    grow_object_root(root, 1024L).unwrap()
    let selected = if foreign {
      {
        ..row_workspace(10000),
        growth: Some(working_growth_fixture(_ => Ok(()))),
      }
    } else {
      workspace
    }
    assert_true(
      reserve_measured_text_buffer(root, selected, 1024, 1026) is Err(_),
    )
    assert_eq(calls.val, if foreign { 0 } else { 1 })
    assert_eq(root.root.text_capacity, Some(0L))
    assert_eq(growth.text, 0L)
    assert_eq(workspace.live, 0)
    release_expression_root(root).unwrap()
    assert_eq(budget.live, 0L)
    assert_eq(growth.logical, 0L)
  }
}

///|
test "measured Text cannot construct after its original root is revoked by current callback" {
  let original : Ref[ExpressionRootLease?] = Ref(None)
  let (growth, workspace, budget, root) = measured_text_root_fixture(_ => {
    release_expression_root(original.val.unwrap()).unwrap()
    Ok(())
  })
  original.val = Some(root)
  grow_object_root(root, 1024L).unwrap()
  assert_true(
    reserve_measured_text_buffer(root, workspace, 1024, 1026)
    is Err(InvalidRootLifetime),
  )
  assert_eq(budget.live, 0L)
  assert_eq(growth.text, 0L)
  assert_eq(workspace.live, 0)
  assert_true(growth.failed)
  assert_eq(growth.funded, measured_text_capacity(1024, 1026).unwrap())
}
