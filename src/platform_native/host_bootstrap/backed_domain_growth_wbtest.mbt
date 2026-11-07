///|
// Actual Resource reservation -> same-provider mmap/attachment -> original
// child-first close. The selected runtime-values fixture keeps its test/Common
// controls in the existing component runtime. Its full private view matches
// the installed local-domain constructor; an offset subview is not growable.
// This fixture proves no normal Read heap
// constructor certificate, Journal caller or logical-to-physical byte tariff.
test "Native domain working growth charges the whole same-parent addition before physical acquisition" {
  let original : BootstrapTestOriginal = { identity: 911, }
  let child : BootstrapTestOriginal = { identity: 912, }
  let page = test_page_bytes_ffi()
  println("domain-growth: supplier")
  let supplier = prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    64L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 256L * page,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire(original).unwrap() {
    Acquired(value) => value
    Pending(_, _) => fail("original root acquisition refused")
  }
  println("domain-growth: acquired")
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
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
      backed_test_limits(16L * page),
      0L,
      0L,
    )
    .unwrap() {
    Lent(value) => value
    Pending(_, _) => fail("same original local loan refused")
  }
  let view = match
    host.view_backed_region_in_process(original, loan, child).unwrap() {
    Mapped(value) => value
    PendingView(_, _) => fail("same original local view refused")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(value) => value
    DomainPending(_, _) => fail("same original domain refused")
  }
  println("domain-growth: original domain")
  host.transfer_backed_domain(original, domain, child).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  println("domain-growth: prepare supplier")
  host.prepare_backed_domain_growth(original, domain, child).unwrap()
  println("domain-growth: supplier prepared")
  let ledger = host.ledger
  let capacity = host.capacity
  let control = host.control.unwrap()
  let usage = host.usage()
  let before_capacity = host.capacity_usage().capacity
  let before_allocated = host.capacity_usage().allocated
  let before_control = @resources.shared_allocation_usage(control).bytes
  let original_description = host
    .backed_domain_capacity(original, domain, child)
    .unwrap()
  host.enter_backed_domain(original, domain, child).unwrap()
  println("domain-growth: entered")
  let physical_before = host
    .observe_backed_domain_inventory(original, domain, child)
    .unwrap()
  // The existing Root policy refuses before mmap, then the exact physical
  // quote can be cancelled. There is no leaked new pending serial or token.
  assert_true(
    host.grow_backed_domain_working(original, domain, child, 512L * page)
    is Err(_),
  )
  assert_eq(host.usage(), usage)
  assert_eq(backing_capacity_bytes_ffi(host.backing), before_capacity)
  assert_true(host.growth is None && domain.working_growth_serial is None)
  println("domain-growth: quoted refusal returned")
  host.grow_backed_domain_working(original, domain, child, 32L * page).unwrap()
  println("domain-growth: grown")
  let physical_after = host
    .observe_backed_domain_inventory(original, domain, child)
    .unwrap()
  assert_true(physical_after.capacity_bytes > physical_before.capacity_bytes)
  let after = host.capacity_usage()
  assert_true(after.capacity > before_capacity)
  assert_eq(backing_capacity_bytes_ffi(host.backing), after.capacity)
  assert_eq(host.usage().reserved_execution_bytes, after.capacity)
  assert_eq(
    after.allocated - before_allocated,
    after.capacity - before_capacity,
  )
  assert_eq(
    @resources.shared_allocation_usage(control).bytes - before_control,
    after.capacity - before_capacity,
  )
  assert_true(
    physical_equal(host.ledger, ledger) &&
    physical_equal(host.capacity, capacity),
  )
  assert_true(host.growth is None && domain.working_growth_serial is None)
  println("domain-growth: observed")
  host.leave_backed_domain(original, domain, child).unwrap()
  assert_eq(
    host.backed_domain_capacity(original, domain, child).unwrap(),
    original_description,
  )
  assert_eq(host.usage().attempts, usage.attempts)
  assert_eq(host.usage().transferred_bytes, usage.transferred_bytes)
  // Stop alone returns none of this newly mapped physical holding.
  host.return_borrow(original, scope).unwrap()
  assert_true(host.try_close(original) is Err(_))
  assert_eq(host.usage().reserved_execution_bytes, after.capacity)
  println("domain-growth: cleanup")
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_view(original, view, child).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  println("domain-growth: root close")
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}
