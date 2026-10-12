///|
/// Arithmetic/lifecycle fixtures only. These quantities are not an adopted
/// Host layout profile and no physical Account/Source/Provider is opened.
fn host_setup_test_profile() -> HolderEffectHostSetupProfile {
  {
    read_ceiling: 32,
    setup_retained_bytes: 120L,
    current_retained_bytes: 30L,
    execution_bytes: 20L,
    string_bytes: 2L,
    utf16_unit_bytes: 2L,
    array_bytes: 2L,
    array_slot_bytes: 2L,
    tuple_bytes: 2L,
    retained_controls_bytes: 10L,
  }
}

///|
fn host_setup_test_site(max_operations : Int) -> @site.ExecutionSite {
  @site.create_site("test", 1, "runtime", max_operations, 1, 150L, 40L).unwrap()
}

///|
test "missing Host setup profile reserves nothing and never checks physical binding" {
  let site = host_setup_test_site(2)
  let checks = [0]
  assert_true(
    begin_holder_effect_host_setup_scope(site, None, () => {
      checks[0] += 1
      true
    })
    is None,
  )
  assert_eq(checks[0], 0)
  assert_eq(@site.site_status(site)[2], 0L)
  assert_eq(@site.site_status(site)[7], 0L)
}

///|
test "nested current check reuses original setup operation" {
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let observed = [0L, 0L]
  assert_true(
    with_holder_effect_host_read_scope(scope, () => {
      observed[0] = @site.site_status(site)[2]
      observed[1] = @site.site_status(site)[7]
      true
    }),
  )
  assert_eq(observed, [1L, 120L])
  assert_eq(scope.depth, 1)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[2], 0L)
  assert_eq(@site.site_status(site)[7], 0L)
}

///|
test "snapshot holding stays charged until actual caller retirement" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let snapshot = [("n", "v")]
  // Independent arithmetic: controls10 + array2 + root(2+2) +
  // slot2 + tuple2 + two Strings each(2+2) = 28.
  assert_eq(
    holder_effect_host_snapshot_extent(scope.profile, "r", snapshot),
    Some(28L),
  )
  assert_true(retain_holder_effect_host_snapshot(scope, "r", snapshot))
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[6], 28L)
  assert_eq(@site.site_status(site)[7], 0L)
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  let holding = scope.holding.unwrap()
  scope.holding = None
  assert_true(@site.release_site_holding(holding))
  assert_eq(@site.site_status(site)[6], 0L)
}

///|
test "setup and dispatch use unchanged Site ceiling and operation slots" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  assert_true(@site.start_site_operation(site, 31L, 1L) is None)
  let dispatch = @site.start_site_operation(site, 30L, 20L).unwrap()
  assert_true(enter_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[2], 2L)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(@site.settle_site_operation(dispatch))
  assert_eq(@site.site_status(site)[7], 0L)
}

///|
test "binding revocation refuses current without retaining a cached Allow" {
  let site = host_setup_test_site(2)
  let current = Ref(true)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => current.val,
  ).unwrap()
  assert_true(leave_holder_effect_host_read_scope(scope))
  current.val = false
  let reads = [0]
  assert_false(
    with_holder_effect_host_read_scope(scope, () => {
      reads[0] += 1
      true
    }),
  )
  assert_eq(reads[0], 0)
  assert_eq(@site.site_status(site)[7], 0L)
}

///|
test "original failed read stays charged until same cleanup is observed" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  guard @bounded_files.read_bounded_text_file_with_custody(
      "unopened", "unread", 0L,
    )
    is Err(failure) else {
    fail("invalid limit admitted")
  }
  observe_holder_effect_host_read_failure(scope, failure)
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_false(enter_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[7], 120L)
  assert_eq(@site.site_status(site)[5], 1L)
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  assert_true(failure.issue() is @bounded_files.InvalidLimit)
  assert_eq(@site.site_status(site)[7], 0L)
  // Confirmed physical retirement does not itself return the cleanup token.
  assert_eq(@site.site_status(site)[5], 1L)
  let cleanup = scope.cleanup.unwrap()
  scope.cleanup = None
  assert_true(@site.release_site_cleanup(cleanup))
  assert_eq(@site.site_status(site)[5], 0L)
}

///|
test "one-pass retirement returns same pending scope without polling or duplicate cleanup" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  guard retire_holder_effect_host_scope(scope)
    is HostSetupScopePending(original) else {
    fail("active operation was retired")
  }
  assert_eq(original.depth, 1)
  assert_eq(@site.site_status(site)[2], 1L)
  assert_eq(@site.site_status(site)[5], 1L)
  assert_eq(@site.site_status(site)[7], 120L)
  assert_true(
    retire_holder_effect_host_scope(original) is HostSetupScopePending(_),
  )
  assert_eq(@site.site_status(site)[5], 1L)
  // A current scope cannot start another read after retirement was requested.
  assert_false(enter_holder_effect_host_read_scope(original))
  assert_false(leave_holder_effect_host_read_scope(original))
  assert_eq(scope.depth, 0)
  assert_true(
    retire_holder_effect_host_scope(original) is HostSetupReadyToDetach,
  )
  assert_eq(@site.site_status(site)[5], 1L)
  let cleanup = scope.cleanup.unwrap()
  scope.cleanup = None
  assert_true(@site.release_site_cleanup(cleanup))
}

///|
test "Site stop and revoke do not acknowledge setup cleanup or return its reservation" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  @site.begin_site_teardown(site)
  @site.revoke_site(site)
  assert_true(
    retire_holder_effect_host_scope(scope) is HostSetupScopePending(_),
  )
  assert_eq(@site.site_status(site)[2], 1L)
  assert_eq(@site.site_status(site)[5], 1L)
  assert_eq(@site.site_status(site)[7], 120L)
}
