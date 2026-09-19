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
