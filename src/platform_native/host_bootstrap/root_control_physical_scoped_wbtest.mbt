///|
// Only this closed fixture issues construction facts: pinned Bytes(32) makes
// one header + 32 payload bytes + one terminator. No Request-layout conclusion
// follows from it. Every later cohort remains charged until original close.
test "actual root controls grow with retained aliases on the same physical owner" {
  let original : BootstrapTestOriginal = { identity: 902, }
  let page = test_page_bytes_ffi()
  let supplier = prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    4L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 32L * page,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => fail("root control acquisition failed")
  }
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let construction : NativeControlConstruction = {
    maximum_managed_request: managed_value_layout_ffi(0) + 33L,
    allocation_requests: 1L,
  }
  let first : Ref[Bytes?] = Ref(None)
  let second : Ref[Bytes?] = Ref(None)
  host.prepare_root_control(original, scope, construction).unwrap()
  let control = host.root_control.unwrap()
  let original_claim = control.claim
  assert_eq(control.bytes, 2L * page)
  assert_true(host.enter_root_control(original, scope))
  first.val = Some(Bytes::make(32, 71))
  let nested = enter_root_control_ffi(host.backing)
  let outer_leave = leave_scope_ffi(host.backing)
  host.leave_root_control(original).unwrap()
  assert_true(nested != 0 && outer_leave != 0)
  assert_eq(scope.scopes, 1L)
  let blocker = host.allocate(original, page).unwrap()
  let before = host.usage()
  assert_true(host.extend_root_control(original, scope, construction) is Err(_))
  assert_eq(host.usage(), before)
  assert_eq(control.bytes, 2L * page)
  // Actual root acquisition precedes the next claim. The earlier bytes remain
  // live; extending controls neither replaces their owner nor recycles credit.
  host.grow_backing(original, scope, 16L * page).unwrap()
  host.extend_root_control(original, scope, construction).unwrap()
  assert_true(physical_equal(control.claim, original_claim))
  assert_eq(control.bytes, 3L * page)
  assert_true(host.enter_root_control(original, scope))
  second.val = Some(Bytes::make(32, 72))
  host.leave_root_control(original).unwrap()
  assert_eq(first.val.unwrap()[0], 71)
  assert_eq(second.val.unwrap()[0], 72)
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  assert_true(host.try_close(original) is Err(_))
  assert_false(control.physical_retired)
  assert_eq(@resources.shared_allocation_usage(original_claim).bytes, 3L * page)
  first.val = None
  assert_true(host.try_close(original) is Err(_))
  second.val = None
  host.try_close(original).unwrap()
  assert_true(blocker.released && control.closed && control.owner is None)
  assert_true(@resources.shared_allocation_usage(original_claim).released)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  host.try_close(original).unwrap()
}

///|
// Identity-only transitions do not construct Request controls. Their complete
// allocation inventory remains a separate prerequisite for the real issuer.
test "Request control scope recognizes only the exact enclosing root and live child" {
  let original = { identity: 903, }
  let foreign_original = { identity: 904, }
  let child = { identity: 905, }
  let host = test_host(original)
  let foreign = test_host(foreign_original)
  let page = test_page_bytes_ffi()
  let allocation = host.allocate(original, 24L * page).unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let loan = match
    host
    .lend_backed_region_in_process(
      original,
      region,
      scope,
      child,
      {
        offset: 0L,
        length: 24L * page,
        payload_offset: page,
        payload_length: 16L * page,
      },
      @resources.ExclusiveWrite,
      backed_test_limits(16L * page),
      0L,
      0L,
    )
    .unwrap() {
    Lent(value) => value
    Pending(_, _) => fail("root-control child loan unavailable")
  }
  let view = match
    host.view_backed_region_in_process(original, loan, child).unwrap() {
    Mapped(value) => value
    PendingView(_, _) => fail("root-control child view unavailable")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(value) => value
    DomainPending(_, _) => fail("root-control child domain unavailable")
  }
  host.transfer_backed_domain(original, domain, child).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  host.prepare_backed_read_context(original, domain, child).unwrap()
  assert_eq(request_control_scope_ffi(host.backing, domain.physical), 1)
  host.enter_borrow_scope(original, scope).unwrap()
  host
  .prepare_root_control(original, scope, {
    maximum_managed_request: managed_value_layout_ffi(0) + 33L,
    allocation_requests: 1L,
  })
  .unwrap()
  assert_eq(request_control_scope_ffi(host.backing, domain.physical), 0)
  assert_true(host.enter_root_control(original, scope))
  let own = request_control_scope_ffi(host.backing, domain.physical)
  let wrong = request_control_scope_ffi(foreign.backing, domain.physical)
  let nested_child = enter_read_context_ffi(domain.physical)
  host.leave_root_control(original).unwrap()
  assert_eq(own, 1)
  assert_eq(wrong, 0)
  assert_true(nested_child != 0)
  assert_false(domain.live_child_attempted)
  host.leave_borrow_scope(original, scope).unwrap()
  host.enter_backed_read_context(original, domain, child).unwrap()
  let child_active = request_control_scope_ffi(host.backing, domain.physical)
  host.leave_backed_read_context(original, domain, child).unwrap()
  assert_eq(child_active, 0)
  host.close_backed_read_context(original, domain, child).unwrap()
  host.close_backed_domain(original, domain, child).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  assert_true(host.enter_root_control(original, scope))
  let stale = request_control_scope_ffi(host.backing, domain.physical)
  host.leave_root_control(original).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  assert_eq(stale, 0)
  host.close_backed_view(original, view, child).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
  foreign.try_close(foreign_original).unwrap()
}

///|
// Selected Native success path: seven Unit-Ok records, SharedAllocation + Ok,
// external extent including its finalizer, NativeBootstrapAllocation, the
// first eight-reference children backing, and final Ok. The largest raw request
// is that backing (8 references + Moon header). Physical payload is separate.
test "completed Host child aliases retire before enclosing controls while escaped wrappers remain" {
  let original = { identity: 906, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let scope = host.borrow_backing(original).unwrap()
  let retained : Ref[NativeBootstrapAllocation[BootstrapTestOriginal]?] = Ref(
    None,
  )
  host.enter_borrow_scope(original, scope).unwrap()
  host
  .prepare_root_control(original, scope, {
    maximum_managed_request: managed_value_layout_ffi(0) +
    8L * managed_value_layout_ffi(4),
    allocation_requests: 13L,
  })
  .unwrap()
  assert_true(host.enter_root_control(original, scope))
  retained.val = Some(host.allocate(original, page).unwrap())
  host.leave_root_control(original).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  assert_true(host.try_close(original) is Err(_))
  assert_true(retained.val.unwrap().released)
  assert_true(host.children.is_empty())
  assert_false(host.root_control.unwrap().physical_retired)
  retained.val = None
  host.try_close(original).unwrap()
  assert_true(host.root_control.unwrap().physical_retired)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}

///|
test "actual root cohort finish reconciles retired pages while escaped controls stay charged" {
  let original : BootstrapTestOriginal = { identity: 908, }
  let page = test_page_bytes_ffi()
  let supplier = prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    12L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 32L * page,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => fail("root cohort fixture acquisition refused")
  }
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  // SAME closed constructor used by the earlier physical control fixture.
  // Three requests bound this cohort, never the Host's lifetime call count.
  let construction : NativeControlConstruction = {
    maximum_managed_request: managed_value_layout_ffi(0) + 33L,
    allocation_requests: 3L,
  }
  let first : Ref[Bytes?] = Ref(None)
  let second : Ref[Bytes?] = Ref(None)
  host.prepare_root_control(original, scope, construction).unwrap()
  let control = host.root_control.unwrap()
  let claim = control.claim
  let usage = host.usage()
  assert_eq(control.bytes, 4L * page)
  let generation = root_control_generation_ffi(host.backing)
  assert_true(generation > 0L)
  assert_true(
    finish_root_control_cohort_ffi(host.backing, generation + 1L) < 0L,
  )
  assert_true(host.enter_root_control(original, scope))
  first.val = Some(Bytes::make(32, 71))
  let active_finish = finish_root_control_cohort_ffi(host.backing, generation)
  host.leave_root_control(original).unwrap()
  assert_true(active_finish < 0L)
  host.finish_root_control_cohort(original, scope).unwrap()
  assert_eq(control.bytes, 2L * page)
  assert_true(physical_equal(control.claim, claim))
  assert_eq(host.usage(), usage)
  assert_eq(first.val.unwrap()[0], 71)
  host
  .extend_root_control(original, scope, {
    maximum_managed_request: construction.maximum_managed_request,
    allocation_requests: 2L,
  })
  .unwrap()
  assert_eq(control.bytes, 4L * page)
  assert_true(root_control_generation_ffi(host.backing) > generation)
  assert_true(host.enter_root_control(original, scope))
  second.val = Some(Bytes::make(32, 72))
  host.leave_root_control(original).unwrap()
  host.finish_root_control_cohort(original, scope).unwrap()
  assert_true(control.bytes >= 2L * page && control.bytes <= 3L * page)
  assert_eq(first.val.unwrap()[0], 71)
  assert_eq(second.val.unwrap()[0], 72)
  first.val = None
  host.finish_root_control_cohort(original, scope).unwrap()
  assert_eq(control.bytes, 2L * page)
  assert_eq(second.val.unwrap()[0], 72)
  second.val = None
  host.finish_root_control_cohort(original, scope).unwrap()
  assert_eq(control.bytes, page)
  // More actual cohorts than the initial window could retain simultaneously.
  // Physical retirement, not constructor-history reset, keeps the charge flat.
  let mut previous_generation = root_control_generation_ffi(host.backing)
  for _ in 0..<4 {
    host
    .extend_root_control(original, scope, {
      maximum_managed_request: construction.maximum_managed_request,
      allocation_requests: 1L,
    })
    .unwrap()
    let next_generation = root_control_generation_ffi(host.backing)
    assert_true(next_generation > previous_generation)
    previous_generation = next_generation
    assert_true(host.enter_root_control(original, scope))
    second.val = Some(Bytes::make(32, 73))
    host.leave_root_control(original).unwrap()
    assert_eq(second.val.unwrap()[0], 73)
    second.val = None
    host.finish_root_control_cohort(original, scope).unwrap()
    assert_eq(control.bytes, page)
    assert_true(physical_equal(control.claim, claim))
    assert_eq(host.usage(), usage)
  }
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
  assert_true(control.closed && control.owner is None)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}

///|
// Same bounded initial Resident assembly, without parser, Site, services or Run.
// The original next-control allowance must remain outside the child payload.

///|
test "initial domain assembly keeps distinct control phases on the same Root" {
  let original = { identity: 909, }
  let capacity = 256L * 1048576L
  let supplier = prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    capacity,
    {
      planning_work: 64,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: capacity,
    },
    16L * 1048576L,
  ).unwrap()
  let host = match supplier.acquire(original).unwrap() {
    Acquired(value) => value
    Pending(_, _) => fail("initial assembly acquisition pending")
  }
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  host.prepare_backed_read_control(original, scope).unwrap()
  assert_true(host.enter_backed_read_control(original, scope))
  let bytes = host.initial_payload_capacity(original).unwrap()
  let allocation = host.allocate_in_process_domain(original, bytes).unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let control = host.root_control.unwrap()
  let same_claim = control.claim
  host.leave_backed_read_control(original, scope).unwrap()
  assert_true(control.cohort_finished && !control.active)
  host.prepare_backed_read_control(original, scope).unwrap()
  assert_true(physical_equal(control.claim, same_claim))
  assert_false(control.cohort_finished)
  assert_true(host.enter_backed_read_control(original, scope))
  let loan = match
    host
    .lend_backed_region_in_process(
      original,
      region,
      scope,
      original,
      { offset: 0L, length: bytes, payload_offset: 0L, payload_length: bytes, },
      @resources.ExclusiveWrite,
      {
        planning_work: 16,
        attempts: 1,
        holdings: 1,
        transfer_bytes: 0L,
        retained_bytes: 0L,
        execution_bytes: bytes,
      },
      0L,
      0L,
    )
    .unwrap() {
    Lent(value) => value
    Pending(_, _) => fail("initial assembly loan pending")
  }
  let view = match
    host.view_backed_region_in_process(original, loan, original).unwrap() {
    Mapped(value) => value
    PendingView(_, _) => fail("initial assembly view pending")
  }
  host.leave_backed_read_control(original, scope).unwrap()
  assert_true(control.cohort_finished && !control.active)
  host.prepare_backed_read_control(original, scope).unwrap()
  assert_true(physical_equal(control.claim, same_claim))
  assert_true(host.enter_backed_read_control(original, scope))
  let domain = match
    host.acquire_backed_domain(original, view, original).unwrap() {
    DomainReady(value) => value
    DomainPending(_, _) => fail("initial assembly domain pending")
  }
  host.transfer_backed_domain(original, domain, original).unwrap()
  host.leave_backed_read_control(original, scope).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  host.close_backed_domain(original, domain, original).unwrap()
  host.close_backed_view(original, view, original).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, original, None)
  .unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}
