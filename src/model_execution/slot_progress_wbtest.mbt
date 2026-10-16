///|
// Real prepared rows/Model startup and synthetic byte envelopes. This proves
// nominal progress custody only, not a parallel window or physical funding.
test "original Model Slot progress refuses copied foreign and reclaimed records" {
  let first_rows = prepared_capacity_test_rows()
  let second_rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let first = original_startup_test_start(
    first_rows,
    original_startup_test_grant(first_rows, limits, None),
    limits,
    None,
  ).unwrap()
  let second = original_startup_test_start(
    second_rows,
    original_startup_test_grant(second_rows, limits, None),
    limits,
    None,
  ).unwrap()
  let original = first.state.progress
  let copied = { ..original, }
  assert_true(model_slot_progress_owned(first.state, original))
  assert_false(model_slot_progress_owned(first.state, copied))
  assert_false(model_slot_progress_owned(first.state, second.state.progress))
  assert_false(model_slot_progress_owned(second.state, original))
  assert_true(request_model_cancel(first))
  assert_true(advance_model_execution(first, 1).unwrap() is Stopped(_, _, _))
  first.state.output_uses = 1
  assert_false(cleanup_model_execution(first).unwrap())
  assert_true(model_slot_progress_owned(first.state, original))
  first.state.output_uses = 0
  assert_true(cleanup_model_execution(first).unwrap())
  assert_false(model_slot_progress_owned(first.state, original))
  assert_true(@relation.cleanup_prepared_infer_rows(first_rows))
  assert_true(request_model_cancel(second))
  assert_true(advance_model_execution(second, 1).unwrap() is Stopped(_, _, _))
  assert_true(cleanup_model_execution(second).unwrap())
  assert_true(@relation.cleanup_prepared_infer_rows(second_rows))
}
