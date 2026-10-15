///|
fn host_read_domain_test_slot(name : String) -> @slot.NativeExecutorSlot raise {
  let root = @env.get_env_var("ACTQL_TEST_HOST_READ_DOMAIN_ROOT").unwrap()
  let slot = @slot.open_native_executor_slot(root + "/" + name).unwrap()
  assert_true(slot.try_acquire().unwrap())
  slot
}

///|
/// Ordinary Native stock-runtime fixture only. The parent supplies a fresh
/// writable FD; these disposable quantities do not install a product profile.
fn host_read_domain_test_original(
  original : @slot.NativeExecutorSlot,
  operation : @site.SiteOperation,
) -> (
  @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
  @bootstrap.NativeBackedExecutionDomain[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ],
  () -> Unit raise,
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
    @bootstrap.Acquired(host) => host
    @bootstrap.Pending(_, _) => fail("original FD backing unavailable")
  }
  host
  .claim(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
  )
  .unwrap()
  let allocation = host.allocate(original, 262144L).unwrap()
  let region : @bootstrap.NativeBackedExecutionRegion[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let borrow = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, borrow).unwrap()
  let loan = match
    host
    .lend_backed_region(
      original,
      region,
      borrow,
      operation,
      {
        offset: 0L,
        length: 262144L,
        payload_offset: 0L,
        payload_length: 262144L,
      },
      @resources.ExclusiveWrite,
      {
        planning_work: 2,
        attempts: 1,
        holdings: 1,
        transfer_bytes: 3L,
        retained_bytes: 0L,
        execution_bytes: 262144L,
      },
      0L,
      0L,
    )
    .unwrap() {
    @bootstrap.Lent(loan) => loan
    @bootstrap.Pending(_, _) => fail("original FD loan unavailable")
  }
  let view = match
    host.map_backed_view(original, loan, operation, fd).unwrap() {
    @bootstrap.Mapped(view) => view
    @bootstrap.PendingView(_, _) => fail("original FD view unavailable")
  }
  let domain = match
    host.acquire_backed_domain(original, view, operation).unwrap() {
    @bootstrap.DomainReady(domain) => domain
    @bootstrap.DomainPending(_, _) => fail("original FD domain unavailable")
  }
  host.transfer_backed_domain(original, domain, operation).unwrap()
  let close_parent = () => {
    host.close_backed_view(original, view, operation).unwrap()
    host
    .settle_backed_region_after_owner_ack(original, loan, operation, None)
    .unwrap()
    assert_true(host.close_backed_region(original, region).unwrap())
    host.leave_borrow_scope(original, borrow).unwrap()
    host.return_borrow(original, borrow).unwrap()
    host.try_close(original).unwrap()
    assert_eq(host.usage().reserved_execution_bytes, 0L)
  }
  (host, domain, close_parent)
}

///|
fn host_read_domain_test_retire(
  scope : HolderEffectHostSetupScope,
) -> Unit raise {
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  let (retained, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(retained.unwrap()))
}

///|
test "missing original read installation retains Site reservation without selecting a substitute" {
  let slot = host_read_domain_test_slot("read-missing.slot")
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let before = @site.site_status(site)
  assert_false(install_holder_effect_host_read_domain(scope, slot, None))
  assert_true(scope.read_domain is None)
  assert_eq(@site.site_status(site), before)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  let (retained, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(retained.unwrap()))
  assert_true(slot.close())
}

///|
test "read installation callback retirement cannot return a current Site scope" {
  let slot = host_read_domain_test_slot("read-reentrant.slot")
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let selected = Ref(0)
  assert_false(
    install_holder_effect_host_read_domain(
      scope,
      slot,
      Some({
        select: (_, _) => {
          selected.val += 1
          scope.retiring = true
          None
        },
      }),
    ),
  )
  assert_eq(selected.val, 1)
  assert_false(holder_effect_host_read_scope_current(scope))
  assert_eq(@site.site_status(site)[7], 120L)
  host_read_domain_test_retire(scope)
  assert_true(slot.close())
}

///|
test "stock runtime read initialization failure keeps the exact installed domain through cleanup" {
  let slot = host_read_domain_test_slot("read-stock.slot")
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let operation = scope.caller_operation.unwrap()
  let (host, domain, close_parent) = host_read_domain_test_original(
    slot, operation,
  )
  let calls = Ref(0)
  let installation : HolderEffectHostReadInstallation = {
    select: (actual_slot, actual_operation) => {
      if physical_equal(actual_slot, slot) &&
        physical_equal(actual_operation, operation) {
        calls.val += 1
        Some((host, domain))
      } else {
        None
      }
    },
  }
  assert_false(
    install_holder_effect_host_read_domain(scope, slot, Some(installation)),
  )
  let original = scope.read_domain.unwrap()
  assert_true(physical_equal(original.host, host))
  assert_true(physical_equal(original.domain, domain))
  assert_false(original.ready)
  assert_false(original.active)
  assert_false(holder_effect_host_read_scope_current(scope))
  assert_false(
    install_holder_effect_host_read_domain(scope, slot, Some(installation)),
  )
  assert_eq(calls.val, 1)
  assert_eq(@site.site_status(site)[7], 120L)
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_domain is None)
  // Parent mapping/loan/Host/FD retirement is independent from domain ACK.
  close_parent()
  let (retained, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(retained.unwrap()))
  assert_true(slot.close())
}

///|
test "foreign original Slot cannot adopt or close another installed read domain" {
  let original_slot = host_read_domain_test_slot("read-original.slot")
  let foreign_slot = host_read_domain_test_slot("read-foreign.slot")
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
    () => true,
  ).unwrap()
  let operation = scope.caller_operation.unwrap()
  let (host, domain, close_parent) = host_read_domain_test_original(
    original_slot, operation,
  )
  assert_false(
    install_holder_effect_host_read_domain(
      scope,
      foreign_slot,
      Some({ select: (_, _) => Some((host, domain)), }),
    ),
  )
  assert_true(scope.read_domain is None)
  host.require_backed_domain_current(original_slot, domain, operation).unwrap()
  host.close_backed_domain(original_slot, domain, operation).unwrap()
  close_parent()
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  let (retained, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(@site.settle_site_operation(retained.unwrap()))
  assert_true(foreign_slot.close())
  assert_true(original_slot.close())
}

///|
test "missing physical domain does not install or invoke the full Store current callback" {
  let site = host_setup_test_site(1)
  let scope = reserve_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    1024L,
  ).unwrap()
  scope.preparation_binding = Some(() => true)
  let before = @site.site_status(site)
  let stores = Ref(0)
  assert_false(
    install_holder_effect_host_store_current(scope, () => {
      stores.val += 1
      true
    }),
  )
  assert_eq(stores.val, 0)
  assert_true(scope.current_binding is None)
  assert_false(holder_effect_host_read_scope_current(scope))
  assert_eq(@site.site_status(site), before)
  host_read_domain_test_retire(scope)
}
