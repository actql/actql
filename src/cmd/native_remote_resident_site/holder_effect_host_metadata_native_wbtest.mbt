///|
/// All tuple/control records in this fixture are prepared before the child
/// allocator is entered. Quantities remain disposable fixture arithmetic.
fn host_metadata_test_scope(
  name : String,
) -> (
  @site.ExecutionSite,
  HolderEffectHostSetupScope,
  @slot.NativeExecutorSlot,
  @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
  HolderEffectHostReadInstallation,
) raise {
  let slot = host_read_domain_test_slot(name)
  let (host, allocation) = host_read_parent_test_host(slot)
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
    slot,
    host_read_parent_test_selection(host, allocation, fd),
  ).unwrap()
  (site, scope, slot, host, installed)
}

///|
test "Site holding and cleanup controls survive original read-domain retirement" {
  let (site, scope, slot, host, installed) = host_metadata_test_scope(
    "metadata-retirement.slot",
  )
  let snapshot : Array[(String, String)] = []
  let operation = scope.caller_operation.unwrap()
  assert_true(
    install_holder_effect_host_read_domain(scope, slot, Some(installed)),
  )
  // Physical accounting only: this fixture performs no Store/Account lookup
  // and the predicate is not a product permission/current supplier.
  assert_true(install_holder_effect_host_store_current(scope, () => true))
  assert_true(retain_holder_effect_host_snapshot(scope, "", snapshot))
  assert_true(
    with_holder_effect_host_site_metadata(scope, () => {
      scope.cleanup = Some(@site.retain_site_cleanup(site))
      true
    }),
  )
  assert_true(holder_effect_host_read_scope_current(scope))
  assert_true(leave_holder_effect_host_read_scope(scope))
  // Both original nominal tokens are deliberately still live. If either was
  // allocated in the child it would retain that context and prevent this ACK.
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_domain is None)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_true(scope.holding is Some(_))
  assert_true(scope.cleanup is Some(_))
  assert_true(@site.site_status(site)[6] > 0L)
  assert_true(@site.site_status(site)[7] > 0L)
  assert_true(@site.release_site_holding(scope.holding.unwrap()))
  scope.holding = None
  assert_true(@site.release_site_cleanup(scope.cleanup.unwrap()))
  scope.cleanup = None
  let (same_operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(physical_equal(same_operation.unwrap(), operation))
  assert_true(@site.settle_site_operation(operation))
  assert_true(slot.close())
}

///|
test "metadata commit survives refused reentry and uses the original cleanup" {
  let (site, scope, slot, host, installed) = host_metadata_test_scope(
    "metadata-reentry.slot",
  )
  let operation = scope.caller_operation.unwrap()
  assert_true(
    install_holder_effect_host_read_domain(scope, slot, Some(installed)),
  )
  let read = scope.read_domain.unwrap()
  assert_false(
    with_holder_effect_host_site_metadata(scope, () => {
      scope.holding = @site.retain_site_operation_holding(operation, 8L)
      // Local current-refusal injection only, not a kernel failure or close ACK.
      // Keep the exact domain/parent handles for original physical retirement.
      read.ready = false
      true
    }),
  )
  assert_true(scope.retiring)
  assert_false(read.active)
  assert_true(physical_equal(scope.read_domain.unwrap(), read))
  assert_true(scope.holding is Some(_))
  assert_eq(@site.site_status(site)[6], 8L)
  assert_eq(@site.site_status(site)[7], 112L)
  assert_true(quiesce_holder_effect_host_setup_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_domain is None)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_true(@site.release_site_holding(scope.holding.unwrap()))
  scope.holding = None
  let (same_operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(physical_equal(same_operation.unwrap(), operation))
  assert_true(@site.settle_site_operation(operation))
  assert_true(slot.close())
}

///|
test "one physical leave cannot authorize metadata under an outstanding nested borrow" {
  let (_, scope, slot, host, installed) = host_metadata_test_scope(
    "metadata-nested.slot",
  )
  let updates = Ref(0)
  let operation = scope.caller_operation.unwrap()
  assert_true(
    install_holder_effect_host_read_domain(scope, slot, Some(installed)),
  )
  let read = scope.read_domain.unwrap()
  // This is an independently owned physical nesting, outside the scope's
  // ordinary depth counter. Its Owner must return its own borrow explicitly.
  host.enter_backed_read_context(slot, read.domain, operation).unwrap()
  assert_false(
    with_holder_effect_host_site_metadata(scope, () => {
      updates.val += 1
      true
    }),
  )
  assert_eq(updates.val, 0)
  assert_true(scope.retiring)
  assert_true(read.active)
  host
  .require_backed_read_context_current(slot, read.domain, operation)
  .unwrap()
  host.leave_backed_read_context(slot, read.domain, operation).unwrap()
  assert_true(quiesce_holder_effect_host_setup_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_domain is None)
  assert_true(scope.read_parent is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_true(scope.holding is None)
  assert_true(scope.cleanup is None)
  let (same_operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(physical_equal(same_operation.unwrap(), operation))
  assert_true(@site.settle_site_operation(operation))
  assert_true(slot.close())
}
