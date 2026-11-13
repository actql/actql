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
  assert_true(host.borrow_request_read_frame(live, input) is Err(_))
  assert_true(host.prepare_domain_initialization_child(domain, input) is Err(_))
  let foreign = { ..host, }
  assert_true(foreign.prepare_request_admission(live, input) is Err(_))
  assert_true(host.prepare_request_admission(live, Ref(43)) is Err(_))
  let initial = host.prepare_request_admission(live, input).unwrap()
  assert_true(host.prepare_request_admission(live, input) is Err(_))
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let ledger = @resources.start_backed_preparation_admission(initial, input).unwrap()
  assert_true(host.borrow_request_read_frame(live, input) is Err(_))
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
  assert_true(foreign.borrow_request_read_frame(live, input) is Err(_))
  assert_true(host.borrow_request_read_frame(live, Ref(43)) is Err(_))
  assert_true(
    physical_equal(host.borrow_request_read_frame(live, input).unwrap(), frame),
  )
  assert_true(
    physical_equal(host.borrow_request_read_frame(live, input).unwrap(), frame),
  )
  held.val = Some(Bytes::make(32, input.val.to_byte()))
  host.leave_domain_read(domain).unwrap()
  assert_true(host.close_request_preparation(live) is Err(_))
  // Pending logical cleanup monotonically fences ordinary observation. The
  // identity-only cleanup observer does not require a current admission.
  assert_true(host.borrow_request_read_frame(live, input) is Err(_))
  assert_true(
    host.observe_request_read_cleanup_scope(live, input)
    is Ok(@bootstrap.BackedReadUnentered),
  )
  host.enter_domain_read_cleanup(domain).unwrap()
  assert_true(
    host.observe_request_read_cleanup_scope(live, input)
    is Ok(@bootstrap.BackedReadEntered),
  )
  assert_true(host.borrow_request_read_frame(live, input) is Err(_))
  assert_true(foreign.observe_request_read_cleanup_scope(live, input) is Err(_))
  assert_true(host.observe_request_read_cleanup_scope(live, Ref(43)) is Err(_))
  host.leave_domain_read(domain).unwrap()
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
  assert_true(host.borrow_request_read_frame(live, input) is Err(_))
  assert_true(host.observe_request_read_cleanup_scope(live, input) is Err(_))
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
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
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
    @resources.backed_preparation_original_frame(initial, input)
    is Err(AlreadyConsumed),
  )
  host.enter_domain_read(domain).unwrap()
  assert_true(
    physical_equal(host.borrow_request_read_frame(live, input).unwrap(), frame),
  )
  host.leave_domain_read(domain).unwrap()
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

///|
// Real Common Request entrance and teardown. The initial controller/Ledger
// constructors deliberately remain in the original outer control lifetime.
// This diagnostic emits their selected Native layouts; its finite physical
// fixture is not a proof of the logical quote's Native representation or an
// installed CLI prefix. Variable Request construction is not exercised here.
test "actual Common Request entrance keeps its controller outside child Read retirement" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "common-request-entrance",
  )
  let input = Ref(71)
  let live = match host.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("Common Request live pending")
  }
  let initial = host.prepare_request_admission(live, input).unwrap()
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let policy = @client.client_local_resource_policy()
  let quoted = @client.client_request_preparation_control_capacity(policy).unwrap()
  // Current shared fixed control: 234 headers, 418 references, 482 words,
  // plus the unchanged installed 4096-byte group; no variable body capacity.
  assert_eq(quoted, (234L * 16L + 418L * 8L + 482L * 8L + 4096L, 0L))
  // Native's issued limits narrow the immutable ordinary policy. No policy
  // ceiling is allocated or asserted to be the actual physical fixture size.
  let owner = @client.begin_backed_request_preparation(initial, input, policy).unwrap()
  let before = @client.request_preparation_accounting(owner)
  assert_eq(before, (quoted.0, 0L, 0L, quoted.0, quoted.0, 0L))
  assert_true(
    physical_equal(
      frame,
      @resources.backed_preparation_original_frame(initial, input).unwrap(),
    ),
  )
  let held : Ref[Bytes?] = Ref(None)
  host.enter_domain_read(domain).unwrap()
  held.val = Some(Bytes::make(32, input.val.to_byte()))
  host.leave_domain_read(domain).unwrap()
  // Common settles only its original logical token. Its initial admission
  // still requires the same Native physical owner's independently observed ACK.
  assert_true(
    @client.abort_request_preparation_after_cleanup(owner)
    is Err(Initial(@resources.Unavailable)),
  )
  assert_eq(
    @client.request_preparation_accounting(owner),
    (0L, 0L, 0L, quoted.0, 0L, 0L),
  )
  assert_true(@resources.imported_child_retirement_readiness(frame).unwrap())
  assert_true(host.close_request_preparation(live) is Err(_))
  assert_eq(held.val.unwrap()[0], 71)
  held.val = None
  host.close_request_preparation(live).unwrap()
  @client.abort_request_preparation_after_cleanup(owner).unwrap()
  @client.abort_request_preparation_after_cleanup(owner).unwrap()
  host.close_request_preparation(live).unwrap()
  initialization_physical_finish(host, domain, descriptor)
}
