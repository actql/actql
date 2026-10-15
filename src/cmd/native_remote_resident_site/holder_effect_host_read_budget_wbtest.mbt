///|
test "read budget requires both original physical payload and delegated quota" {
  let profile = host_setup_test_profile()
  // Independent fixture: initial retained120 + workspace20 = 140. This is
  // compatibility arithmetic, not the physical Account parser's funding proof.
  assert_true(holder_effect_host_read_budget_fits(profile, 140L, 140L))
  assert_true(holder_effect_host_read_budget_fits(profile, 141L, 140L))
  assert_false(holder_effect_host_read_budget_fits(profile, 139L, 140L))
  assert_false(holder_effect_host_read_budget_fits(profile, 140L, 139L))
  for unavailable in [0L, -1L] {
    assert_false(
      holder_effect_host_read_budget_fits(profile, unavailable, 140L),
    )
    assert_false(
      holder_effect_host_read_budget_fits(profile, 140L, unavailable),
    )
  }
  let overflow = {
    ..profile,
    setup_retained_bytes: 9223372036854775800L,
    execution_bytes: 20L,
  }
  assert_false(
    holder_effect_host_read_budget_fits(
      overflow, 9223372036854775807L, 9223372036854775807L,
    ),
  )
}

///|
test "original small delegation refuses read initialization and retains parent cleanup" {
  let original = host_read_domain_test_slot("read-budget.slot")
  let (host, allocation) = host_read_parent_test_host(original)
  let fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_FD").unwrap(),
  )
  let selected = host_read_parent_test_selection(host, allocation, fd)
  let selected = {
    ..selected,
    limits: { ..selected.limits, execution_bytes: 139L, },
  }
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let installed = prepare_holder_effect_host_read_parent(
    scope, original, selected,
  ).unwrap()
  assert_false(
    install_holder_effect_host_read_domain(scope, original, Some(installed)),
  )
  // This differs from stock-runtime initialization failure: the original
  // nominal parent/domain exists, but no read-use/context was initialized.
  assert_true(scope.read_domain is None)
  let parent = scope.read_parent.unwrap()
  assert_true(parent.domain is Some(_))
  assert_true(parent.loan is Some(_))
  assert_false(parent.borrow_active)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[7], 120L)
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  let (operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_true(original.close())
}
