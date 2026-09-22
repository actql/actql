///|
test "workspace release underflow poisons later reservations" {
  let workspace = row_workspace(4)
  assert_true(reserve_slots(workspace, 2))
  release_slots(workspace, 3)
  assert_false(workspace_healthy(workspace))
  assert_eq(workspace.live, -1)
  assert_false(reserve_slots(workspace, 1))
}

///|
test "slot scope releases temporary entries and retains exact survivors" {
  let workspace = row_workspace(8)
  let scope = begin_slot_scope(workspace, 2).unwrap()
  assert_true(reserve_slots(workspace, 3))
  assert_true(scope.close(keep=1))
  assert_eq(workspace.live, 1)
  assert_eq(workspace.peak, 5)
  assert_true(workspace_healthy(workspace))
  release_slots(workspace, 1)
  assert_eq(workspace.live, 0)
}

///|
test "slot scope rejects impossible keep and repeated close" {
  let first = row_workspace(4)
  let impossible = begin_slot_scope(first, 1).unwrap()
  assert_false(impossible.close(keep=2))
  assert_false(workspace_healthy(first))

  let second = row_workspace(4)
  let repeated = begin_slot_scope(second, 1).unwrap()
  assert_true(repeated.close())
  assert_false(repeated.close())
  assert_false(workspace_healthy(second))
}

///|
test "scoped slots roll back partial failure and reject poisoned success" {
  let failed = row_workspace(8)
  assert_true(
    with_scoped_slots(failed, fn() -> Result[Unit, RowIssue] {
      if !reserve_slots(failed, 5) {
        return Err(RowLimit)
      }
      Err(RowLimit)
    })
    is Err(RowLimit),
  )
  assert_eq(failed.live, 0)

  let poisoned = row_workspace(8)
  assert_true(
    with_scoped_slots(poisoned, fn() -> Result[Unit, RowIssue] {
      release_slots(poisoned, 1)
      Ok(())
    })
    is Err(RowLimit),
  )
  assert_eq(poisoned.live, 0)

  let disguised = row_workspace(8)
  assert_true(
    with_scoped_slots(disguised, fn() -> Result[Unit, RowIssue] {
      release_slots(disguised, 1)
      Err(InvalidRows)
    })
    is Err(RowLimit),
  )
  assert_eq(disguised.live, 0)
}
