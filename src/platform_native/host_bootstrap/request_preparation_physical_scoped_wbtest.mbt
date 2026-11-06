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
