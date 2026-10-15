///|
/// This fixture requires the ordinary unentered Native test caller. Arithmetic
/// quantities are fixture-only; they do not install a funded Host profile.
test "Host Account read does not substitute Site capacity for an original Native read context" {
  // Establish that the exact source checkout is readable through the legacy
  // physical entry. A missing path cannot make the scoped refusal pass.
  let readable = match
    @bounded_files.read_bounded_text_file_with_custody(
      ".",
      "moon.mod",
      4096L,
      diagnostic_ceiling=Some(8),
    ) {
    Ok(text) => text
    Err(failure) => {
      failure.retry_cleanup().unwrap()
      fail("the original source fixture is not physically readable")
    }
  }
  assert_false(readable.is_empty())
  let site = host_setup_test_site(1)
  let checks = Ref(0)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some({ ..host_setup_test_profile(), read_ceiling: 4096, }),
    1024L,
    () => {
      checks.val += 1
      true
    },
  ).unwrap()
  let operation = scope.caller_operation.unwrap()
  let reserved = @site.site_status(site)
  assert_true(
    read_holder_effect_host_text(scope, ".", "moon.mod", 4096L) is None,
  )
  let original = scope.pending.unwrap()
  assert_true(
    original.issue() is @bounded_files.Filesystem(@filesystem.RootOpen(_)),
  )
  let pending_status = reserved.copy()
  // One original cleanup token is retained in addition to unchanged capacity.
  pending_status[5] += 1L
  assert_eq(@site.site_status(site), pending_status)
  assert_true(physical_equal(scope.caller_operation.unwrap(), operation))
  let before_retry = checks.val
  assert_true(
    read_holder_effect_host_text(scope, ".", "moon.mod", 4096L) is None,
  )
  assert_eq(checks.val, before_retry)
  assert_true(physical_equal(scope.pending.unwrap(), original))
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  // Physical refusal cleanup cannot itself settle the upper caller's charge.
  assert_eq(@site.site_status(site)[7], 120L)
  let (retained, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(physical_equal(retained.unwrap(), operation))
  assert_true(@site.settle_site_operation(operation))
  assert_false(@site.settle_site_operation(operation))
  let cleanup = scope.cleanup.unwrap()
  scope.cleanup = None
  assert_true(@site.release_site_cleanup(cleanup))
}
