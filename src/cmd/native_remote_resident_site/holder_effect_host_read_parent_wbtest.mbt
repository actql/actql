///|
/// Disposable actual Owner fixture, not an installed Host/profile. The parent
/// process supplies a fresh FD for each case and retains its descriptor duty.
fn host_read_parent_test_host(
  original : @slot.NativeExecutorSlot,
) -> (
  @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
  @bootstrap.NativeBootstrapAllocation[@slot.NativeExecutorSlot],
) raise {
  let fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_FD").unwrap(),
  )
  let supplier = @bootstrap.prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    1048576L,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 1048576L,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire_fd(original, fd).unwrap() {
    @bootstrap.Acquired(value) => value
    @bootstrap.Pending(_, _) => fail("original parent backing unavailable")
  }
  host
  .claim(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
  )
  .unwrap()
  (host, host.allocate(original, 262144L).unwrap())
}

///|
fn host_read_parent_test_selection(
  host : @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
  allocation : @bootstrap.NativeBootstrapAllocation[@slot.NativeExecutorSlot],
  fd : Int,
) -> HolderEffectHostReadParentInstallation {
  {
    host,
    allocation,
    fd,
    extent: {
      offset: 0L,
      length: 262144L,
      payload_offset: 0L,
      payload_length: 262144L,
    },
    limits: {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 0L,
      execution_bytes: 262144L,
    },
    overhead_retained: 0L,
    overhead_execution: 0L,
  }
}

///|
test "parent installation refusal leaves the original Host before acquisition" {
  let original = host_read_domain_test_slot("parent-refused.slot")
  let (host, allocation) = host_read_parent_test_host(original)
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_preparation_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  assert_true(
    prepare_holder_effect_host_read_parent(
      scope,
      original,
      host_read_parent_test_selection(host, allocation, -1),
    )
    is None,
  )
  assert_true(scope.read_parent is None)
  host.require_current(original).unwrap()
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  host.try_close(original).unwrap()
  let (operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_true(original.close())
}

///|
test "foreign FD mapping keeps the exact partial parent through cleanup" {
  let original = host_read_domain_test_slot("parent-foreign-fd.slot")
  let (host, allocation) = host_read_parent_test_host(original)
  let foreign_fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_FOREIGN_FD").unwrap(),
  )
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_preparation_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let installed = prepare_holder_effect_host_read_parent(
    scope,
    original,
    host_read_parent_test_selection(host, allocation, foreign_fd),
  ).unwrap()
  assert_false(
    install_holder_effect_host_read_domain(scope, original, Some(installed)),
  )
  let parent = scope.read_parent.unwrap()
  assert_true(parent.attempted)
  assert_true(parent.view is Some(_))
  assert_true(parent.loan is Some(_))
  let original_view = parent.view.unwrap()
  let original_loan = parent.loan.unwrap()
  assert_true(parent.domain is None)
  assert_true(scope.read_domain is None)
  assert_false(
    install_holder_effect_host_read_domain(scope, original, Some(installed)),
  )
  assert_true(physical_equal(scope.read_parent.unwrap(), parent))
  assert_true(
    physical_equal(scope.read_parent.unwrap().view.unwrap(), original_view),
  )
  assert_true(
    physical_equal(scope.read_parent.unwrap().loan.unwrap(), original_loan),
  )
  assert_eq(@site.site_status(site)[7], 120L)
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  let (operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_true(original.close())
}

///|
test "failed read context closes domain and original parent before Site reservation" {
  let original = host_read_domain_test_slot("parent-stock.slot")
  let (host, allocation) = host_read_parent_test_host(original)
  let fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_FD").unwrap(),
  )
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_preparation_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  // Full Store current is deliberately unavailable before actual context entry.
  scope.current_binding = None
  let stores = Ref(0)
  let installed = prepare_holder_effect_host_read_parent(
    scope,
    original,
    host_read_parent_test_selection(host, allocation, fd),
  ).unwrap()
  assert_false(
    install_holder_effect_host_read_domain(scope, original, Some(installed)),
  )
  assert_false(
    install_holder_effect_host_store_current(scope, () => {
      stores.val += 1
      true
    }),
  )
  assert_eq(stores.val, 0)
  assert_true(scope.current_binding is None)
  let parent = scope.read_parent.unwrap()
  assert_false(parent.borrow_active)
  assert_true(parent.domain is Some(_))
  assert_true(scope.read_domain is Some(_))
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_domain is None)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_eq(@site.site_status(site)[7], 120L)
  let (operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(original.close())
}

///|
test "parent Host close waits for the same outstanding borrow and retries once returned" {
  let original = host_read_domain_test_slot("parent-close-pending.slot")
  let (host, allocation) = host_read_parent_test_host(original)
  let observer = host.borrow_backing(original).unwrap()
  let fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_FD").unwrap(),
  )
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_preparation_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let installed = prepare_holder_effect_host_read_parent(
    scope,
    original,
    host_read_parent_test_selection(host, allocation, fd),
  ).unwrap()
  assert_false(
    install_holder_effect_host_read_domain(scope, original, Some(installed)),
  )
  let parent = scope.read_parent.unwrap()
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(
    retire_holder_effect_host_scope(scope) is HostSetupScopePending(_),
  )
  assert_true(physical_equal(scope.read_parent.unwrap(), parent))
  assert_true(scope.read_domain is None)
  assert_true(parent.view is None)
  assert_true(parent.loan is None)
  assert_eq(@site.site_status(site)[7], 120L)
  assert_true(host.usage().reserved_execution_bytes > 0L)
  host.return_borrow(original, observer).unwrap()
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  let (operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_true(original.close())
}

///|
test "current callback cannot replace the retained original parent before acquisition" {
  let original = host_read_domain_test_slot("parent-current-replacement.slot")
  let (host, allocation) = host_read_parent_test_host(original)
  let fd : Int = @string.from_str(
    @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_FD").unwrap(),
  )
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_preparation_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let installed = prepare_holder_effect_host_read_parent(
    scope,
    original,
    host_read_parent_test_selection(host, allocation, fd),
  ).unwrap()
  let parent = scope.read_parent.unwrap()
  let operation = scope.caller_operation.unwrap()
  scope.preparation_binding = Some(() => {
    scope.read_parent = None
    true
  })
  assert_true((installed.select)(original, operation) is None)
  assert_false(parent.attempted)
  assert_true(parent.region is None)
  host.require_current(original).unwrap()
  // The fixture restores its captured original responsibility for cleanup;
  // this is not a replacement supplier or a physical close acknowledgement.
  scope.read_parent = Some(parent)
  scope.preparation_binding = Some(() => true)
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_parent is None)
  let (operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_true(original.close())
}
