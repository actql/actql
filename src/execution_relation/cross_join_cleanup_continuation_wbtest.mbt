///|
test "failed Cross Join exposes only actual private reclamation progress" {
  let rows = Array::makei(32, index => "{\"id\":" + index.to_string() + "}").join(
    ",",
  )
  let (_, started, reads) = bounded_cross_fixture(
    max_rows=32,
    max_work=100000,
    left_rows="[" + rows + "]",
    right_rows="[{\"tag\":\"a\"}]",
    output_values={
      max_nodes: 95,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
  )
  let active = started.unwrap()
  assert_eq(bounded_cross_join_cleanup_continuation(active), -1L)
  let failed = Ref(false)
  for _ in 0..<100000 {
    match advance_bounded_cross_join(active, 1).unwrap() {
      BoundedCrossJoinContinue(..) => ()
      BoundedCrossJoinFailed(Capture(CaptureLimit), ..) => {
        failed.val = true
        break
      }
      _ => fail("retain the original output CaptureLimit")
    }
  }
  assert_true(failed.val)
  let output = active.state.output.unwrap()
  assert_true(output.buffer.rows.length() >= 24)
  // Terminal is not a reclamation witness; the first real cleanup slice
  // establishes runnable private work and counts exactly its removed roots.
  assert_eq(bounded_cross_join_cleanup_continuation(active), -1L)
  assert_false(cleanup_bounded_cross_join(active).unwrap())
  assert_true(bounded_cross_join_cleanup_pending(active))
  assert_eq(bounded_cross_join_cleanup_continuation(active), 64L)
  let work = output.buffer.budget.work
  let mut previous = 64L
  for _ in 0..<10 {
    if cleanup_bounded_cross_join(active).unwrap() {
      break
    }
    let cursor = bounded_cross_join_cleanup_continuation(active)
    assert_true(cursor > previous && cursor - previous <= 64L)
    previous = cursor
  }
  assert_false(bounded_cross_join_cleanup_pending(active))
  assert_eq(bounded_cross_join_cleanup_continuation(active), -1L)
  assert_eq(output.buffer.budget.work, work)
  assert_true(reads.all(producer_read_available))
  // A no-op cleanup remains distinct from reclaimed custody.
  assert_false(cleanup_bounded_cross_join(active).unwrap())
}
