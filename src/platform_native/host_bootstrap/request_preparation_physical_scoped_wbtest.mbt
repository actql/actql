///|
// Actual selected-provider fixture of downstream partial acquisition, not a
// normal CLI profile. Logical region closing supplies no physical ACK.
test "Request live access refusal preserves cleanup after its original read return" {
  let original = { identity: 111, }
  let child = { identity: 112, }
  let input = Ref(113)
  let host = test_host(original)
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
    Pending(_, _) => fail("Request partial fixture loan unavailable")
  }
  let view = match
    host.view_backed_region_in_process(original, loan, child).unwrap() {
    Mapped(value) => value
    PendingView(_, _) => fail("Request partial fixture view unavailable")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(value) => value
    DomainPending(_, _) => fail("Request partial fixture domain unavailable")
  }
  host.transfer_backed_domain(original, domain, child).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.prepare_backed_read_context(original, domain, child).unwrap()
  assert_false(
    @resources.close_backed_execution_region(region.accounting, host).unwrap(),
  )
  // Target the private issuer after a real original logical refusal. Public
  // preparation also checks currentness before reaching this downstream step.
  let live = match
    host
    .issue_backed_live_child_from_read(original, domain, child, input, Request)
    .unwrap() {
    LiveChildReady(_) =>
      fail("closing original unexpectedly admitted live access")
    LiveChildPending(value, _) => value
  }
  assert_true(live.access is None)
  assert_true(
    host.prepare_backed_request_admission(original, live, input) is Err(_),
  )
  assert_true(live.request_preparation is Some(_))
  assert_false(domain.read_retired)
  host.close_backed_request_preparation(original, live).unwrap()
  assert_true(domain.read_retired && domain.read_use is None)
  assert_true(live.retired && live.original is None && live.runtime is None)
  host.close_backed_request_preparation(original, live).unwrap()
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_view(original, view, child).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  host.try_close(original).unwrap()
}

///|
// Layout/custody consumer for the public running-census boundary. Setup and
// retirement controls remain in the enclosing test lifetime. The disposable
// arena is diagnostic storage, NOT a NativeWorking constructor certificate.
// In particular, equal logical totals still replace LedgerUsage and can grow
// the three original scalar buffers while their previous storage is live.
test "actual anonymous Request census grows at equal totals and retains old usage aliases" {
  let original = { identity: 121, }
  let child = { identity: 122, }
  let input = Ref(123)
  let body = Ref(124)
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let allocation = host
    .allocate_in_process_domain(original, 24L * page)
    .unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
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
        payload_offset: 0L,
        payload_length: 24L * page,
      },
      @resources.ExclusiveWrite,
      {
        planning_work: 16,
        attempts: 4,
        holdings: 4,
        transfer_bytes: 0L,
        retained_bytes: 8L * page,
        execution_bytes: 8L * page,
      },
      0L,
      0L,
    )
    .unwrap() {
    Lent(value) => value
    Pending(_, _) => fail("census fixture loan unavailable")
  }
  let view = match
    host.view_backed_region_in_process(original, loan, child).unwrap() {
    Mapped(value) => value
    PendingView(_, _) => fail("census fixture view unavailable")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(value) => value
    DomainPending(_, _) => fail("census fixture domain unavailable")
  }
  host.transfer_backed_domain(original, domain, child).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.prepare_backed_read_context(original, domain, child).unwrap()
  let live = match
    host
    .prepare_backed_request_live_child(original, domain, child, input)
    .unwrap() {
    LiveChildReady(value) => value
    LiveChildPending(_, _) => fail("census fixture Request unavailable")
  }
  let initial = host
    .prepare_backed_request_admission(original, live, input)
    .unwrap()
  let ledger = @resources.start_backed_preparation_admission(initial, input).unwrap()
  let owner : @resources.PreparationCapacity[Ref[Int], Ref[Int]] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    4096L,
    4096L,
    max_borrowers=1,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    owner, input,
  ).unwrap()
  @resources.complete_preparation_capacity(owner, input, body, 4096L, 4096L).unwrap()
  @resources.claim_original_ledger_run_binding(identity, ledger).unwrap()
  @resources.transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let old : Ref[@resources.LedgerUsage?] = Ref(None)
  host.enter_backed_read_context(original, domain, child).unwrap()
  @resources.grow_running_preparation_capacity_inventory(
    owner, input, body, identity, 4096L, 4096L, 32, 32, 32,
  ).unwrap()
  old.val = Some(@resources.ledger_usage(ledger))
  // Cross the selected allocator's slab threshold using actual int32 buffers.
  @resources.grow_running_preparation_capacity_inventory(
    owner, input, body, identity, 4096L, 4096L, 2048, 2048, 2048,
  ).unwrap()
  let same_values = @resources.ledger_usage(ledger) == old.val.unwrap()
  let replaced = !physical_equal(
    @resources.ledger_usage(ledger),
    old.val.unwrap(),
  )
  @resources.grow_running_preparation_capacity_inventory(
    owner, input, body, identity, 4096L, 4096L, 2048, 2048, 2048,
  ).unwrap()
  let refused = @resources.grow_running_preparation_capacity_inventory(
      owner,
      input,
      body,
      identity,
      9L * page,
      4096L,
      4096,
      4096,
      4096,
    )
    is Err(@resources.Resource(@resources.RetentionLimit))
  host.leave_backed_read_context(original, domain, child).unwrap()
  assert_true(same_values && replaced && refused)
  assert_eq(old.val.unwrap().reserved_retention_bytes, 4096L)
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_true(@resources.retire_preparation_capacity(owner).unwrap())
  // The old child-owned snapshot remains a real Read alias after logical stop.
  assert_true(host.close_backed_request_preparation(original, live) is Err(_))
  old.val = None
  host.close_backed_request_preparation(original, live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_view(original, view, child).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  host.try_close(original).unwrap()
}
