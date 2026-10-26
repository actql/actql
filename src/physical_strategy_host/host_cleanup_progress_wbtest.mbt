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

///|
test "Host cleanup progress owns retry and close-wait sequencing" {
  let progress = begin_host_cleanup_progress()
  assert_eq(
    prepare_host_cleanup_progress_step(progress, true, true, true, false),
    HostCleanupRetryKnown,
  )
  assert_true(!record_host_cleanup_closes_awaited(progress))
  assert_true(record_host_cleanup_retry(progress))
  assert_eq(
    prepare_host_cleanup_progress_step(progress, true, true, true, false),
    HostCleanupAwaitCloses,
  )
  assert_true(record_host_cleanup_closes_awaited(progress))
  assert_true(record_host_cleanup_retry(progress))
  assert_eq(
    prepare_host_cleanup_progress_step(progress, false, false, false, false),
    HostCleanupFinished,
  )
  assert_true(!record_host_cleanup_retry(progress))
}
