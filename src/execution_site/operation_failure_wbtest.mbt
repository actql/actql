///|
test "failed Site operation waits only for required physical stop" {
  assert_eq(
    prepare_failed_site_operation_step(true, false, false),
    FailedSiteAwaitStop,
  )
  assert_eq(
    prepare_failed_site_operation_step(true, true, false),
    FailedSiteSettle,
  )
  assert_eq(
    prepare_failed_site_operation_step(false, false, false),
    FailedSiteSettle,
  )
  assert_eq(
    prepare_failed_site_operation_step(true, false, true),
    FailedSiteFinished,
  )
}

///|
test "failed Site operation progress owns stop and settlement facts" {
  let progress = begin_failed_site_operation_progress(true, false)
  assert_eq(
    prepare_failed_site_operation_progress_step(progress),
    FailedSiteAwaitStop,
  )
  assert_true(!record_failed_site_operation_settlement(progress))
  assert_true(record_failed_site_operation_stop(progress))
  assert_eq(
    prepare_failed_site_operation_progress_step(progress),
    FailedSiteSettle,
  )
  assert_true(record_failed_site_operation_settlement(progress))
  assert_eq(
    prepare_failed_site_operation_progress_step(progress),
    FailedSiteFinished,
  )
  assert_true(record_failed_site_operation_stop(progress))
}

///|
test "retained Site holding follows physical close and cleanup" {
  assert_eq(
    prepare_retained_site_holding_step(false, false, false, false, false, false),
    RetainedSiteStartClose,
  )
  assert_eq(
    prepare_retained_site_holding_step(true, false, false, false, false, false),
    RetainedSiteAwaitClose,
  )
  assert_eq(
    prepare_retained_site_holding_step(true, false, true, true, false, false),
    RetainedSiteAwaitCleanup,
  )
  assert_eq(
    prepare_retained_site_holding_step(true, false, true, true, true, false),
    RetainedSiteReleaseHolding,
  )
  assert_eq(
    prepare_retained_site_holding_step(true, true, false, false, false, false),
    RetainedSiteReleaseHolding,
  )
  assert_eq(
    prepare_retained_site_holding_step(true, true, false, false, false, true),
    RetainedSiteHoldingFinished,
  )
  assert_eq(
    prepare_retained_site_holding_step(true, true, true, false, false, false),
    RetainedSiteHoldingInvalid,
  )
}

///|
test "retained Site progress shares close and releases each holding" {
  let close = begin_retained_site_close_progress()
  let first = begin_retained_site_holding_progress(close).unwrap()
  let second = begin_retained_site_holding_progress(close).unwrap()
  assert_eq(
    prepare_retained_site_close_progress_step(close),
    RetainedSiteCloseStart,
  )
  assert_eq(
    prepare_retained_site_holding_progress_step(first),
    RetainedSiteStartClose,
  )
  assert_true(record_retained_site_close_started(close))
  assert_eq(
    prepare_retained_site_close_progress_step(close),
    RetainedSiteCloseAwaitPhysical,
  )
  assert_true(begin_retained_site_holding_progress(close) is None)
  assert_eq(
    prepare_retained_site_holding_progress_step(first),
    RetainedSiteAwaitClose,
  )
  assert_true(record_retained_site_close_failed(close))
  assert_eq(
    prepare_retained_site_close_progress_step(close),
    RetainedSiteCloseAwaitCleanup,
  )
  assert_eq(
    prepare_retained_site_holding_progress_step(first),
    RetainedSiteAwaitCleanup,
  )
  assert_true(record_retained_site_cleanup_authority(close))
  assert_true(record_retained_site_cleanup_stopped(close))
  assert_eq(
    prepare_retained_site_close_progress_step(close),
    RetainedSiteCloseFinished,
  )
  assert_true(record_retained_site_holding_released(first))
  assert_eq(
    prepare_retained_site_holding_progress_step(first),
    RetainedSiteHoldingFinished,
  )
  assert_eq(
    prepare_retained_site_holding_progress_step(second),
    RetainedSiteReleaseHolding,
  )
  assert_true(record_retained_site_holding_released(second))
  assert_eq(
    prepare_retained_site_holding_progress_step(second),
    RetainedSiteHoldingFinished,
  )
}
