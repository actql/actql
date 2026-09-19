///|
test "Host cleanup retries around closes before deciding terminal state" {
  assert_eq(
    prepare_host_cleanup_step(false, false, false, true, true, true, false),
    HostCleanupRetryKnown,
  )
  assert_eq(
    prepare_host_cleanup_step(true, false, false, true, true, true, false),
    HostCleanupAwaitCloses,
  )
  assert_eq(
    prepare_host_cleanup_step(true, true, false, false, true, true, false),
    HostCleanupRetryKnown,
  )
  assert_eq(
    prepare_host_cleanup_step(true, true, true, false, true, false, true),
    HostCleanupFailed,
  )
  assert_eq(
    prepare_host_cleanup_step(true, true, true, false, true, false, false),
    HostCleanupPending,
  )
  assert_eq(
    prepare_host_cleanup_step(true, false, true, false, false, false, false),
    HostCleanupFinished,
  )
}

///|
test "Host cleanup pending follows current responsibility only" {
  assert_false(host_cleanup_pending(false, false, false))
  assert_true(host_cleanup_pending(true, false, false))
  assert_true(host_cleanup_pending(false, true, false))
  assert_true(host_cleanup_pending(false, false, true))
}
