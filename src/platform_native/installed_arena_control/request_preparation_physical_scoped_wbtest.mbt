///|
// Actual installed-provider component fixtures. Their deliberately finite
// fixture capacity is not ordinary CLI growth or normal Source acceptance.
test "actual Request starts its own pristine census and retains escaped physical aliases" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "request-original",
  )
  let input = Ref(43)
  host.enter_domain_read(domain).unwrap()
  assert_true(host.prepare_domain_request_child(domain, input) is Err(_))
  host.leave_domain_read(domain).unwrap()
  // The refused entered-scope call did not consume the original acquisition.
  let live = match host.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("request live pending")
  }
  assert_true(host.prepare_domain_initialization_child(domain, input) is Err(_))
  let foreign = { ..host, }
  assert_true(foreign.prepare_request_admission(live, input) is Err(_))
  assert_true(host.prepare_request_admission(live, Ref(43)) is Err(_))
  let initial = host.prepare_request_admission(live, input).unwrap()
  assert_true(host.prepare_request_admission(live, input) is Err(_))
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let ledger = @resources.start_backed_preparation_admission(initial, input).unwrap()
  // This reservation succeeds only when Native has not installed the
  // incompatible Initialization bootstrap census before Common's Request.
  let capacity : @resources.PreparationCapacity[Ref[Int], Unit] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    16384L,
    16384L,
    max_borrowers=4,
  ).unwrap()
  let held : Ref[Bytes?] = Ref(None)
  host.enter_domain_read(domain).unwrap()
  held.val = Some(Bytes::make(32, input.val.to_byte()))
  host.leave_domain_read(domain).unwrap()
  assert_true(host.close_request_preparation(live) is Err(_))
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  assert_true(@resources.imported_child_retirement_readiness(frame).unwrap())
  // Logical quiescence alone does not acknowledge the live physical alias.
  assert_true(host.close_request_preparation(live) is Err(_))
  assert_eq(held.val.unwrap()[0], 43)
  assert_true(host.close_domain_after_owner_ack(domain) is Err(_))
  held.val = None
  host.close_request_preparation(live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  host.close_request_preparation(live).unwrap()
  initialization_physical_finish(host, domain, descriptor)
}

///|
test "actual Request issuer closes its retained original frame after Run transfer" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "request-run-transfer",
  )
  let input = Ref(47)
  let live = match host.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("request transfer live pending")
  }
  let initial = host.prepare_request_admission(live, input).unwrap()
  let ledger = @resources.start_backed_preparation_admission(initial, input).unwrap()
  let capacity : @resources.PreparationCapacity[Ref[Int], Ref[Int]] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    16384L,
    16384L,
    max_borrowers=4,
  ).unwrap()
  let body = Ref(48)
  @resources.complete_preparation_capacity(capacity, input, body, 4L, 0L).unwrap()
  let (run, _, retirement, holder) = @resources.adopt_backed_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_true(
    @resources.cleanup_backed_preparation_admission(initial)
    is Err(AlreadyConsumed),
  )
  assert_true(host.close_request_preparation(live) is Err(_))
  assert_false(@resources.retire_transferred_preparation(retirement).unwrap())
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  assert_true(host.close_request_preparation(live) is Err(_))
  assert_true(@resources.release_backed_preparation_holder(run).unwrap())
  assert_true(@resources.retire_transferred_preparation(retirement).unwrap())
  assert_true(@resources.cleanup_backed_prepared_run_admission(run) is Err(_))
  host.close_request_preparation(live).unwrap()
  @resources.cleanup_backed_prepared_run_admission(run).unwrap()
  host.close_request_preparation(live).unwrap()
  initialization_physical_finish(host, domain, descriptor)
}

///|
test "actual Request can close an unstarted retained admission without a fabricated report" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "request-unstarted",
  )
  let input = Ref(53)
  let live = match host.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("request unstarted live pending")
  }
  let initial = host.prepare_request_admission(live, input).unwrap()
  host.close_request_preparation(live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  initialization_physical_finish(host, domain, descriptor)
}
