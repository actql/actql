///|
test "managed failure progression fixes physical cleanup order" {
  assert_eq(
    prepare_managed_failure_step(false, false, false, false, false, false),
    FailureCloseAdditional,
  )
  assert_eq(
    prepare_managed_failure_step(true, false, false, false, false, false),
    FailureCloseOperations,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, true, false, false, false),
    FailureAwaitStop,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, true, true, false, false),
    FailureSettleOperations,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, false, true, false, true),
    FailureSettleOperations,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, false, true, true, true),
    FailureCloseOperations,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, true, true, true, false),
    FailureRefreshCleanup,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, true, true, true, true),
    FailureFinished,
  )
}

///|
test "already settled execution still closes its physical owners first" {
  assert_eq(
    prepare_managed_failure_step(false, false, false, true, true, true),
    FailureCloseAdditional,
  )
  assert_eq(
    prepare_managed_failure_step(true, false, false, true, true, true),
    FailureCloseOperations,
  )
  assert_eq(
    prepare_managed_failure_step(true, true, true, true, true, true),
    FailureFinished,
  )
}

///|
test "managed failure progress owns settlement and cleanup observations" {
  let progress = begin_managed_failure_progress(false, false, false)
  assert_eq(
    prepare_managed_failure_progress_step(progress),
    FailureCloseAdditional,
  )
  assert_true(record_managed_failure_additional_closed(progress))
  assert_eq(
    prepare_managed_failure_progress_step(progress),
    FailureCloseOperations,
  )
  assert_true(record_managed_failure_operations_close_attempted(progress))
  assert_true(record_managed_failure_operations_closed(progress))
  assert_eq(prepare_managed_failure_progress_step(progress), FailureAwaitStop)
  assert_true(record_managed_failure_cleanup_stopped(progress))
  assert_eq(
    prepare_managed_failure_progress_step(progress),
    FailureSettleOperations,
  )
  assert_true(record_managed_failure_execution_settled(progress))
  assert_eq(
    prepare_managed_failure_progress_step(progress),
    FailureRefreshCleanup,
  )
  assert_true(record_managed_failure_cleanup_refreshed(progress))
  assert_eq(prepare_managed_failure_progress_step(progress), FailureFinished)
}
