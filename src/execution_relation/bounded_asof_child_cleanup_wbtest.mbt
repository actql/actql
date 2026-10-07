///|
fn check_bounded_asof_child_cleanup(
  output_sort : Bool,
  fail_budget? : Bool = false,
) -> Unit raise {
  let prefix = "x".repeat(400)
  // Equal clocks make OutputSort compare real source identities too.
  let left_rows_override = if output_sort {
    Some(
      "[{\"id\":\"" +
      prefix +
      "b\",\"key\":1,\"clock\":100,\"priority\":null,\"value\":20}," +
      "{\"id\":\"" +
      prefix +
      "a\",\"key\":1,\"clock\":100,\"priority\":null,\"value\":10}," +
      "{\"id\":\"" +
      prefix +
      "c\",\"key\":2,\"clock\":100,\"priority\":null,\"value\":30}]",
    )
  } else {
    None
  }
  let (control, execution, inputs) = bounded_asof_fixture_result(
    10000,
    if fail_budget {
      256
    } else {
      100000
    },
    text_id=true,
    left_rows_override~,
  ).unwrap()
  let state = execution.state
  let mut reached = false
  let mut previous_progress = 0L
  let mut previous_work = 0L
  // Observe the real comparator paying for a long source identity.
  // The watchdog is not the cancellation boundary.
  for _ in 0..<10000 {
    match advance_bounded_asof_join(execution, 1).unwrap() {
      BoundedAsOfJoinContinue(progress~, work~) => {
        assert_true(work > previous_work && work - previous_work <= 1L)
        previous_progress = progress
        previous_work = work
      }
      _ => fail("as-of stopped before the active sort comparison")
    }
    let in_phase = if output_sort {
      state.phase is OutputSort
    } else {
      state.phase is IdentitySort
    }
    if in_phase &&
      state.sort is Some(_) &&
      state.comparison.phase == 1 &&
      state.comparison.charge.offset > 64 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let child = state.sort.unwrap()
  let remaining_before_stop = state.control.remaining
  let held = state.workspace.live
  let comparison = (
    state.comparison.phase,
    state.comparison.offset,
    state.comparison.charge.offset,
  )
  assert_true(held > 0)
  assert_true(previous_progress > 0L)
  assert_false(bounded_index_sort_stopped(child))
  assert_true(child.token is Some(_))
  assert_true(state.rows.val is None)
  assert_false(state.accepted.val)
  assert_true(inputs.all(producer_read_available))

  if fail_budget {
    // The admitted budget cannot pay for two 401-byte identities. Let the
    // actual comparison exhaust it; do not mutate its control or session.
    let mut failed = false
    for _ in 0..<1000 {
      match advance_bounded_asof_join(execution, 1).unwrap() {
        BoundedAsOfJoinContinue(progress~, work~) => {
          assert_true(work > previous_work && work - previous_work <= 1L)
          previous_progress = progress
          previous_work = work
        }
        BoundedAsOfJoinFailed(Rows(RowLimit), progress~, work~) => {
          assert_eq(progress, previous_progress)
          assert_eq(work, previous_work + 1L)
          failed = true
          break
        }
        _ => fail("as-of did not preserve the child comparison failure")
      }
    }
    assert_true(failed)
    assert_eq(state.control.remaining, 0)
    assert_true(bounded_index_sort_stopped(child))
    assert_true(@bounded.cleanup_pending(child.session))
  } else {
    assert_true(@bounded.request_cancel(control))
    match advance_bounded_asof_join(execution, 1).unwrap() {
      BoundedAsOfJoinStopped(@bounded.Cancelled, progress~, work~) => {
        assert_eq(progress, previous_progress)
        assert_eq(work, previous_work)
      }
      _ => fail("as-of parent did not confirm cancellation")
    }
    // Parent stop alone must retain the live child and its callback state.
    assert_false(bounded_index_sort_stopped(child))
    assert_eq(state.control.remaining, remaining_before_stop)
    assert_eq(
      (
        state.comparison.phase,
        state.comparison.offset,
        state.comparison.charge.offset,
      ),
      comparison,
    )
  }
  let remaining = state.control.remaining
  assert_true(state.sort is Some(_))
  assert_eq(state.workspace.live, held)
  assert_true(state.rows.val is None)
  assert_false(state.accepted.val)
  assert_true(inputs.all(producer_read_available))
  assert_true(bounded_asof_join_cleanup_pending(execution))

  assert_true(cleanup_bounded_asof_join(execution).unwrap())
  assert_false(bounded_asof_join_cleanup_pending(execution))
  assert_true(state.sort is None)
  assert_true(state.output is None)
  assert_true(state.rows.val is None)
  assert_false(state.accepted.val)
  assert_eq(state.workspace.live, 0)
  assert_eq(state.control.remaining, remaining)
  assert_true(inputs.all(producer_read_available))

  // Keep the actual child handle: dropping the parent's field is not proof
  // that the child observed stop and ran its reclamation callback.
  assert_true(bounded_index_sort_stopped(child))
  assert_true(child.token is None)
  assert_false(@bounded.cleanup_pending(child.session))
  assert_false(cleanup_bounded_index_sort(child))
  assert_false(cleanup_bounded_asof_join(execution).unwrap())
  assert_eq(state.workspace.live, 0)
  assert_eq(state.control.remaining, remaining)
  assert_true(inputs.all(producer_read_available))
  if fail_budget {
    // Cleanup of an already failed child must not replace failure with a
    // cancellation request on the shared control.
    assert_true(@bounded.request_cancel(control))
  }
}

///|
test "bounded as-of retains identity sort until confirmed stop and cleanup" {
  check_bounded_asof_child_cleanup(false)
}

///|
test "bounded as-of retains output sort until confirmed stop and cleanup" {
  check_bounded_asof_child_cleanup(true)
}

///|
test "bounded as-of preserves child budget failure through cleanup" {
  check_bounded_asof_child_cleanup(false, fail_budget=true)
}
