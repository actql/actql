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
