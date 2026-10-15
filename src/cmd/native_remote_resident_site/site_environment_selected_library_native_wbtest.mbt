///|
/// Return this helper frame before cleanup: the original failure and temporary
/// diagnostic aliases must not remain live across the child domain close.
fn capture_site_selected_library_failure(
  original : SiteEnvironmentOpenCustody,
  path : String,
) -> Unit raise {
  match @sqlite.load_current_component_with_custody(path, 4096L, 8) {
    Err(@sqlite.CleanupRequired(failure)) => {
      original.failed_sqlite_library = Some(failure)
      assert_true(failure.issue() is @sqlite.LibraryLoad(_))
    }
    Err(@sqlite.RefusedBeforeAcquisition(_)) =>
      fail("required original domain did not acquire Library custody")
    Ok(_) => fail("ordinary SQLite image unexpectedly supplied component ABI")
  }
}

///|
/// Required derived-runtime diagnostic only, not a normal Host/profile. The
/// parent supplies fresh backing and a real non-component SQLite image; missing
/// inputs or an unavailable selected domain fail rather than skip this case.
test "prepared Site failure carrier retires original selected Library and Host before Slot" {
  let root = @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_ROOT").unwrap()
  let slot_path = root + "/selected-library-failure.slot"
  let slot = @slot.open_native_executor_slot(slot_path).unwrap()
  assert_true(slot.try_acquire().unwrap())
  let (host, allocation) = host_read_parent_test_host(slot)
  let fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_FD").unwrap(),
  )
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_preparation_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let operation = scope.caller_operation.unwrap()
  let reserved = @site.site_status(site)
  // Both existing control records belong to the outer caller. No replacement
  // Site, operation or Library is created after a failed acquisition.
  let original = site_environment_open_custody(
    "selected Library preparation failed",
    "original-process",
    original_setup_scope=Some(scope),
  )
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  let installation = prepare_holder_effect_host_read_parent(
    scope,
    slot,
    host_read_parent_test_selection(host, allocation, fd),
  ).unwrap()
  assert_true(
    install_holder_effect_host_read_domain(scope, slot, Some(installation)),
  )
  capture_site_selected_library_failure(original, path)
  let returned = finish_prepared_failed_site_environment_open(custody)
  assert_true(custody.slot_closed)
  assert_false(custody.slot_close_unknown)
  assert_true(original.failed_sqlite_library is None)
  assert_true(original.original_setup_scope is None)
  assert_true(scope.read_domain is None)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_eq(@site.site_status(site), reserved)
  match finish_holder_command(returned) {
    Some(terminal) => {
      assert_true(physical_equal(terminal.operation, operation))
      assert_eq(terminal.failure, "selected Library preparation failed")
      assert_eq(@site.site_status(site), reserved)
      assert_true(@site.settle_site_operation(terminal.operation))
    }
    None => fail("original diagnosis/reservation was lost")
  }
  let next = @slot.open_native_executor_slot(slot_path).unwrap()
  assert_true(next.try_acquire().unwrap())
  assert_true(next.close())
}
