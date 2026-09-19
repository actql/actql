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
