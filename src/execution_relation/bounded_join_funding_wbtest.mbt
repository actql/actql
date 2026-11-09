///|
test "bounded Join requires exact output funding before committing a complete row" {
  // One row root, three Number cells and three UTF-16 name units:
  // 4 * 256 + 3 * 8 = 1048 independently charged bytes.
  for ceiling in [1048L, 1047L] {
    let requests : Array[Int64] = []
    let (_, active, parents) = bounded_join_fixture(
      reserve=Some(bytes => {
        requests.push(bytes)
        if bytes <= ceiling {
          Ok(())
        } else {
          Err(WorkspaceBudgetUnavailable)
        }
      }),
    )
    let buffer = active.state.output.unwrap().buffer
    match finish_bounded_join_test(active) {
      Ok(output) => {
        assert_eq(ceiling, 1048L)
        assert_eq(completed_row_count(output), 1)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
        assert_true(completed_cell(output, 0, 1) is Some(Number(10.0)))
        assert_true(completed_cell(output, 0, 2) is Some(Number(20.0)))
        assert_true(cleanup_bounded_join(active).unwrap())
        assert_eq(completed_row_count(output), 1)
      }
      Err(Capture(CaptureLimit)) => {
        assert_eq(ceiling, 1047L)
        assert_true(buffer.rows.is_empty())
        assert_eq(buffer.budget.retention_funded, 0L)
        assert_true(cleanup_bounded_join(active).unwrap())
      }
      _ => fail("actual before-commit Join funding must decide the row")
    }
    assert_eq(requests[requests.length() - 1], 1048L)
    assert_false(bounded_join_cleanup_pending(active))
    assert_true(parents.all(producer_read_available))
  }
}

///|
test "bounded Join cancellation reclaims funded unpublished rows without releasing parents" {
  let (control, active, parents) = bounded_join_fixture(
    left_rows="[{\"id\":1,\"v\":10},{\"id\":1,\"v\":11}]",
    reserve=Some(_ => Ok(())),
  )
  let buffer = active.state.output.unwrap().buffer
  let mut reached = false
  for _ in 0..<10000 {
    assert_true(
      advance_bounded_join(active, 1).unwrap() is BoundedJoinContinue(..),
    )
    if buffer.rows.length() == 1 {
      reached = true
      break
    }
  }
  assert_true(reached)
  assert_eq(buffer.budget.retention_funded, 1048L)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_join(active, 1).unwrap() is BoundedJoinStopped(_, ..),
  )
  for _ in 0..<10000 {
    cleanup_bounded_join(active).unwrap() |> ignore
    if !bounded_join_cleanup_pending(active) {
      break
    }
  }
  assert_false(bounded_join_cleanup_pending(active))
  assert_true(buffer.rows.is_empty())
  assert_true(active.state.rows.val is None)
  assert_eq(active.state.workspace.live, 0)
  assert_true(parents.all(producer_read_available))
}
