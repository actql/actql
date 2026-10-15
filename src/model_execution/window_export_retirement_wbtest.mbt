///|
// Original startup and cleanup; synthetic grants and a whitebox partial
// projection isolate reference retirement, not physical or public funding.
test "original Model window partial DATA projection retains pending output and retires on cleanup" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let active = original_startup_test_start(rows, grant, limits, None).unwrap()
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
  let original : ModelSlotCapture = {
    slot: 0,
    slot_cid: "sha256:" + "1".repeat(64),
    input_key_cid: "sha256:" + "2".repeat(64),
    fixed_request_cid: "sha256:" + "3".repeat(64),
    provider_id: "models/fixture",
    provider_model: None,
    provider_request_id: None,
    value: model_execution_test_output(task),
    input_tokens: None,
    output_tokens: None,
    observed_at: "2026-10-16T00:00:00.000Z",
  }
  let exported = [original]
  let window : ModelSlotWindow = {
    frames: [None, None, None, None],
    outcomes: {},
    adopted_slots: [],
    export_captures: Some(exported),
    next_slot: 0,
    scan: 0,
  }
  active.state.slot_window = Some(window)
  assert_true(request_model_cancel(active))
  assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
  active.state.output_uses = 1
  assert_false(cleanup_model_execution(active).unwrap())
  assert_true(
    window.export_captures is Some(same) && physical_equal(same, exported),
  )
  assert_eq(exported.length(), 1)
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  active.state.output_uses = 0
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(window.export_captures is None)
  assert_eq(exported.length(), 0)
  assert_eq(exported.capacity(), 0)
  assert_eq(
    original.slot,
    0,
    msg="retiring this array does not mutate escaped records",
  )
  assert_true(active.state.slot_window is None)
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
}
