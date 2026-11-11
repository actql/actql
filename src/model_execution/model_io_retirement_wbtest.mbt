///|
// Whitebox lifetime test: the startup and prepared-set fields use synthetic
// grants and explicit internal construction, not installed admission evidence.
// It tests retirement of the added reference, never a new access/send issuer.
test "original Model IO access reference survives pending cleanup and retires after capacity" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let active = original_startup_test_start(rows, grant, limits, None).unwrap()
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 1, 1).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  let prepared : ModelPreparedCallSet = {
    owner: active,
    scope: None,
    io_access: Some(access),
  }
  active.state.prepared_call_set = Some(prepared)
  let child_closed = Ref(false)
  active.state.physical_cursors.push({
    advance: () => Err(InvalidProvider),
    cleanup: () => child_closed.val,
  })
  assert_true(request_model_cancel(active))
  assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
  active.state.output_uses = 1
  assert_false(cleanup_model_execution(active).unwrap())
  assert_true(prepared.io_access is Some(same) && physical_equal(same, access))
  assert_true(
    active.state.prepared_call_set is Some(same) &&
    physical_equal(same, prepared),
  )
  active.state.output_uses = 0
  assert_false(cleanup_model_execution(active).unwrap())
  assert_true(prepared.io_access is Some(same) && physical_equal(same, access))
  child_closed.val = true
  let foreign = original_startup_test_grant(rows, limits, None)
  active.state.original_startup = Some(foreign)
  assert_true(cleanup_model_execution(active) is Err(RequestIdentity))
  assert_true(prepared.io_access is Some(same) && physical_equal(same, access))
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_true(
    active.state.prepared_call_set is Some(same) &&
    physical_equal(same, prepared),
  )
  active.state.original_startup = Some(grant)
  @resources.settle_capacity(foreign.ledger, foreign.capacity).unwrap()
  assert_true(cleanup_model_execution(active).unwrap())
  // Retire this Model's borrowed reference, not the shared Host admission.
  assert_true(prepared.io_access is None)
  assert_true(active.state.prepared_call_set is None)
  assert_true(prepared_model_call_count(prepared) is None)
  assert_true(@resources.model_io_access_within_limits(access, 1, 1))
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(@resources.close_model_io_access(access).unwrap())
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
}
