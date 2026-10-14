///|
test "failed Site preparation keeps original Slot when process holding is unconfirmed" {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let slot = @slot.open_native_executor_slot(parent + "/site-open-pending.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = site_environment_open_custody(
    "original unavailable hold",
    "original-process",
    release_required=true,
  )
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  assert_false(retry_holder_site_environment_open_cleanup(custody))
  assert_true(original.release_required)
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_false(custody.slot_closed)
  assert_false(retry_holder_site_environment_open_cleanup(custody))
  assert_eq(slot.verify_current_hold(), Ok(()))
  // Only the independent fixture's explicit end retires this real Slot;
  // production cleanup never fabricates release for the missing holding.
  assert_true(slot.close())
}

///|
test "failed Site preparation returns inherited Slot only after original cleanup ACK" {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let slot = @slot.open_native_executor_slot(parent + "/site-open-retired.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = site_environment_open_custody(
    "original preparation refused", "original-process",
  )
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  assert_true(retry_holder_site_environment_open_cleanup(custody))
  assert_true(custody.slot_closed)
  assert_false(custody.slot_close_unknown)
  assert_true(retry_holder_site_environment_open_cleanup(custody))
  let next = @slot.open_native_executor_slot(parent + "/site-open-retired.slot").unwrap()
  assert_true(next.try_acquire().unwrap())
  assert_true(next.close())
  assert_eq(original.original_failure, "original preparation refused")
}
