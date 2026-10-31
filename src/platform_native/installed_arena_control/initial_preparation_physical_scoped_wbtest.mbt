///|
// Actual installed-provider component fixture only, not a normal Source
// numerical profile. It deliberately has the existing small test allowance.
fn initialization_physical_fixture(
  label : String,
) -> (InstalledArenaHost, InstalledArenaDomain, Int) raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let descriptor = process_test_open(
    @utf8.encode(root + "/" + label + ".backing\u{0}"),
    2,
  )
  assert_true(descriptor >= 0)
  let page = domain_page_bytes()
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    64L * page,
    {
      planning_work: 64,
      attempts: 16,
      holdings: 16,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: 64L * page,
    },
    65536L,
  ).unwrap()
  host.acquire_fd(descriptor).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = match
    host
    .prepare_domain(scope, descriptor, 32L * page, {
      planning_work: 16,
      attempts: 4,
      holdings: 4,
      transfer_bytes: 4096L,
      retained_bytes: 8L * page,
      execution_bytes: 24L * page,
    })
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("initialization fixture: domain pending")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.prepare_domain_read(domain).unwrap()
  (host, domain, descriptor)
}

///|
fn initialization_physical_finish(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  descriptor : Int,
) -> Unit raise {
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  assert_eq(process_test_close(descriptor), 0)
}

///|
// This finite component exercises Native assembly and its original working
// token directly. It does not qualify the shared Host's ordinary policy or
// execute a normal Source/Model/Effect/CLI initialization recipe.
test "actual initialization retains its same input and waits for the last physical alias" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "initialization-original",
  )
  let input = Ref(31)
  let live = match
    host.prepare_domain_initialization_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("initialization live pending")
  }
  assert_true(host.prepare_domain_initialization_child(domain, input) is Err(_))
  let budget : @bootstrap.NativeBackedInitializationBudget = {
    bootstrap_retained: 16384L,
    bootstrap_execution: 8192L,
  }
  // NativeBackedLiveChild is opaque outside its defining package; the caller
  // cannot construct a copied carrier. Core copied-admission cases are separate.
  assert_true(host.initialize_preparation(live, Ref(31), budget) is Err(_))
  let foreign = { ..host, }
  assert_true(foreign.initialize_preparation(live, input, budget) is Err(_))
  let initial = host.initialize_preparation(live, input, budget).unwrap()
  assert_true(host.initialize_preparation(live, input, budget) is Err(_))
  let ledger = @resources.take_backed_initialization_admission(initial, input).unwrap()
  assert_true(
    @resources.take_backed_initialization_admission(initial, input) is Err(_),
  )
  let working : @resources.PreparationCapacity[Ref[Int], Unit] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    0L,
    0L,
    max_borrowers=1,
  ).unwrap()
  // The funded inventory has exactly this one token, not a guessed read census.
  assert_true(@resources.reserve_capacity(ledger, 0L, 0L) is Err(_))
  @resources.reserve_working_preparation_phase(working, input, 16384L, 16384L).unwrap()
  let held : Ref[Bytes?] = Ref(None)
  host.enter_domain_read(domain).unwrap()
  held.val = Some(Bytes::make(32, input.val.to_byte()))
  host.leave_domain_read(domain).unwrap()
  assert_true(host.close_preparation(live) is Err(_))
  assert_true(
    @resources.check_backed_initialization_input(initial, input) is Ok(_),
  )
  assert_true(host.close_domain_after_owner_ack(domain) is Err(_))
  assert_true(foreign.close_preparation(live) is Err(_))
  assert_eq(held.val.unwrap()[0], 31)
  held.val = None
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(working, input).unwrap(),
  )
  host.close_preparation(live).unwrap()
  host.close_preparation(live).unwrap()
  assert_true(
    @resources.check_backed_initialization_input(initial, input) is Err(_),
  )
  assert_true(@resources.preparation_capacity_reservation_retired(working))
  initialization_physical_finish(host, domain, descriptor)
}

///|
test "actual initialization bootstrap refusal retains its original start for cleanup" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "initialization-budget-refused",
  )
  let input = Ref(37)
  let live = match
    host.prepare_domain_initialization_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("initialization live pending")
  }
  let page = domain_page_bytes()
  assert_true(
    host.initialize_preparation(live, input, {
      bootstrap_retained: 16384L,
      bootstrap_execution: 24L * page + 1L,
    })
    is Err(@bootstrap.Inventory(@resources.Resource(@resources.ExecutionLimit))),
  )
  assert_true(
    host.initialize_preparation(live, input, {
      bootstrap_retained: 16384L,
      bootstrap_execution: 8192L,
    })
    is Err(_),
  )
  host.close_preparation(live).unwrap()
  host.close_preparation(live).unwrap()
  initialization_physical_finish(host, domain, descriptor)
}
